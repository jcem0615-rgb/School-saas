import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Creates an account for someone else.
 *
 * This one genuinely needs the service role: it mints a Supabase Auth
 * user, which no RLS policy can express. That makes every check in here
 * load-bearing, since nothing downstream will second-guess it.
 *
 * Ported from functions/src/callable/users/provisionUser.ts, matrix and
 * all. Kept explicit rather than "any staff may create any role" so a
 * compromised Registrar session cannot mint itself a Director.
 */

type Role =
  | "owner" | "director" | "principal" | "admin" | "registrar"
  | "faculty" | "staff" | "guidance" | "student" | "parent";

const PROVISIONING_MATRIX: Record<string, Role[]> = {
  // The Owner stands up a new school's leadership: a Director to run it
  // and an Admin to do the setup, without having to sign in as the
  // Director first just to create the Admin.
  owner: ["director", "admin"],
  director: ["admin", "principal", "registrar", "faculty", "staff", "guidance"],
  admin: ["principal", "registrar", "faculty", "staff", "guidance"],
  registrar: ["student", "parent"],
};

// "owner" appears in no row above, and this makes that explicit rather
// than incidental. There is one Owner, established once by
// bootstrap-owner against a server-side email. If a future edit adds
// "owner" to some row by accident, this still refuses -- and behind it,
// the one_owner_only index still refuses.
const UNPROVISIONABLE: Role[] = ["owner"];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/** Random, and long enough to survive any password policy worth having. */
function temporaryPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(18));
  const raw = btoa(String.fromCharCode(...bytes)).replace(/[^a-zA-Z0-9]/g, "");
  return `${raw.slice(0, 14)}Aa1!`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Sign in first." }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Expected a JSON body." }, 400);
  }

  const role = String(body.role ?? "") as Role;
  const schoolId = typeof body.schoolId === "string" ? body.schoolId.trim() : "";
  const email = String(body.email ?? "").trim().toLowerCase();
  const firstName = String(body.firstName ?? "").trim();
  const lastName = String(body.lastName ?? "").trim();

  if (!role || !schoolId || !email || !firstName || !lastName) {
    return json({ error: "Missing required fields." }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: caller, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !caller?.user) return json({ error: "Sign in first." }, 401);

  // The caller's role comes from the database, never from the request.
  const { data: callerProfile, error: profileError } = await admin
    .from("user_profiles")
    .select("role, school_id, status")
    .eq("id", caller.user.id)
    .maybeSingle();
  if (profileError) return json({ error: profileError.message }, 500);
  if (!callerProfile) {
    return json({ error: "Your account is not fully provisioned." }, 403);
  }
  if (callerProfile.status !== "active") {
    return json({ error: "Your account is not active." }, 403);
  }

  if (UNPROVISIONABLE.includes(role)) {
    return json({ error: `A ${role} account cannot be created this way.` }, 403);
  }

  const allowed = PROVISIONING_MATRIX[callerProfile.role] ?? [];
  if (!allowed.includes(role)) {
    return json(
      { error: `Your role (${callerProfile.role}) cannot create a ${role} account.` },
      403,
    );
  }

  // The Owner provisions across schools by design; everyone else is
  // confined to their own tenant.
  if (callerProfile.role !== "owner" && callerProfile.school_id !== schoolId) {
    return json({ error: "You cannot provision users for another school." }, 403);
  }

  // Check the school exists before minting an Auth account, so a bad
  // reference fails cleanly instead of leaving an orphaned login behind.
  const { data: school, error: schoolError } = await admin
    .from("schools").select("id").eq("id", schoolId).maybeSingle();
  if (schoolError) return json({ error: schoolError.message }, 500);
  if (!school) return json({ error: `No school with the id "${schoolId}".` }, 404);

  const password = temporaryPassword();
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { first_name: firstName, last_name: lastName },
  });
  if (createError) {
    return json({ error: createError.message }, createError.status ?? 400);
  }

  const { error: insertError } = await admin.from("user_profiles").insert({
    id: created.user.id,
    school_id: schoolId,
    role,
    status: "active",
    first_name: firstName,
    last_name: lastName,
    email,
    must_change_password: true,
  });

  if (insertError) {
    // The Auth account exists but has no profile, which is an account
    // that can sign in and see nothing. Undo it rather than leave that.
    await admin.auth.admin.deleteUser(created.user.id);
    return json({ error: insertError.message }, 500);
  }

  // Returned once and never stored. The account must change it on first
  // sign-in -- must_change_password is set above.
  return json({ uid: created.user.id, temporaryPassword: password }, 201);
});
