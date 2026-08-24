import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

/**
 * Establishes the single platform Owner, once.
 *
 * Every other account is created by someone who already has one. The
 * Owner is the account with nobody above it, so it cannot be provisioned
 * the ordinary way -- provision-user refuses the role outright. This is
 * the one door, and it is built to be walked through exactly once:
 *
 *   1. The caller must already be signed in. This grants a role; it does
 *      not create credentials, so it cannot be used to mint an account.
 *   2. Their *verified* email must equal the configured owner address,
 *      read server-side. Nothing the client sends is trusted.
 *   3. No owner may exist yet.
 *
 * The third check is not really this function's -- `one_owner_only`, a
 * partial unique index, is what makes a second owner impossible. The
 * check here exists to answer with a sentence instead of a constraint
 * violation. That ordering matters: the guarantee lives in the database,
 * where a future code path with a bug in it still cannot get around it.
 */

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/**
 * The address permitted to claim the owner role.
 *
 * The OWNER_EMAIL secret wins when it is set, so the value can be moved
 * to a real edge-function secret later without touching this code. The
 * fallback is private.app_config, which is reachable only by the service
 * role: no grants to anon or authenticated, RLS with no policies, and a
 * schema PostgREST does not expose.
 */
async function configuredOwnerEmail(admin: SupabaseClient): Promise<string> {
  const fromEnv = (Deno.env.get("OWNER_EMAIL") ?? "").trim().toLowerCase();
  if (fromEnv) return fromEnv;

  const { data, error } = await admin
    .schema("private")
    .from("app_config")
    .select("value")
    .eq("key", "owner_email")
    .maybeSingle();
  if (error || !data?.value) return "";
  return String(data.value).trim().toLowerCase();
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Sign in first, then run this once." }, 401);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const configured = await configuredOwnerEmail(admin);
  if (!configured) {
    // Refusing is the safe failure. No configured address with a
    // permissive fallback would make this an open door to the highest
    // privilege in the system.
    return json({ error: "No owner email is configured for this deployment." }, 500);
  }

  const { data: caller, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !caller?.user) {
    return json({ error: "Sign in first, then run this once." }, 401);
  }

  const email = (caller.user.email ?? "").trim().toLowerCase();
  if (!email || email !== configured) {
    return json({ error: "This account cannot be the owner." }, 403);
  }

  // Without this, anyone able to sign up with an unverified address could
  // claim the configured one on a provider that permits it.
  if (!caller.user.email_confirmed_at) {
    return json(
      { error: "Verify the owner email address before claiming the role." },
      403,
    );
  }

  const { data: existing, error: lookupError } = await admin
    .from("user_profiles")
    .select("id")
    .eq("role", "owner")
    .maybeSingle();
  if (lookupError) return json({ error: lookupError.message }, 500);
  if (existing) return json({ error: "This platform already has an owner." }, 409);

  const meta = caller.user.user_metadata ?? {};
  const { error: insertError } = await admin.from("user_profiles").insert({
    id: caller.user.id,
    // No school_id: the Owner is platform-level and belongs to no tenant.
    // owner_is_platform_level enforces that; passing one would fail here.
    school_id: null,
    role: "owner",
    status: "active",
    first_name: (meta.first_name as string) ?? "Platform",
    last_name: (meta.last_name as string) ?? "Owner",
    email,
  });

  if (insertError) {
    // 23505 is one_owner_only firing between the check above and this
    // insert -- two callers racing. The index is the real guard.
    if (insertError.code === "23505") {
      return json({ error: "This platform already has an owner." }, 409);
    }
    return json({ error: insertError.message }, 500);
  }

  return json({
    ok: true,
    uid: caller.user.id,
    message: "Owner role granted.",
  });
});
