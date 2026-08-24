import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Adds a school to the platform. Owner only.
 *
 * The work happens in public.create_school, not here. Two reasons, both
 * about not being able to get it wrong:
 *
 * A school is two rows -- the school and its subscription -- and half a
 * school is invisible in the Owner's list and unusable by its Director.
 * A Postgres function body runs inside one transaction, so either both
 * land or neither does. supabase-js has no transactions; doing the
 * inserts here would mean a window where one exists without the other.
 *
 * And the call is made with the *caller's* JWT rather than the service
 * role, so RLS still applies: schools_owner_insert is what actually
 * decides, and this function has no privilege to lose. A service-role
 * client here would bypass every policy and put the whole decision in
 * this file.
 */

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Postgres error codes the RPC raises, mapped to what they mean over HTTP.
const STATUS_FOR: Record<string, number> = {
  "42501": 403, // insufficient_privilege -- not the owner
  "22023": 400, // invalid_parameter_value -- bad name, id or rate
  "23505": 409, // unique_violation -- that id is taken
};

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

  const name = typeof body.name === "string" ? body.name : "";
  const rate = Number(body.billingRatePerStudent);
  if (!name.trim()) return json({ error: "The school needs a name." }, 400);
  if (!Number.isFinite(rate) || rate < 0) {
    return json({ error: "Billing rate must be zero or more." }, 400);
  }

  const asCaller = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    },
  );

  const { data, error } = await asCaller.rpc("create_school", {
    p_name: name,
    p_billing_rate: rate,
    // Left null, the database slugifies the name. Deliberately not done
    // here: there were already two slugify implementations that
    // disagreed on accented names, and a third would be a third answer.
    p_school_id: typeof body.schoolId === "string" ? body.schoolId : null,
    p_address_line: typeof body.addressLine === "string" ? body.addressLine : null,
    p_contact_email: typeof body.contactEmail === "string" ? body.contactEmail : null,
    p_contact_phone: typeof body.contactPhone === "string" ? body.contactPhone : null,
  });

  if (error) {
    return json({ error: error.message }, STATUS_FOR[error.code ?? ""] ?? 500);
  }

  // The id the database settled on, which the caller cannot predict when
  // it was derived from the name -- and which they need to provision the
  // school's Director next.
  return json({ schoolId: data }, 201);
});
