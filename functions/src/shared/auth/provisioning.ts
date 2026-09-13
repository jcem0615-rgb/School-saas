/**
 * Who may create an account, and for which role.
 *
 * Kept here rather than inside provisionUser.ts so it can be read and
 * tested without standing up a Functions runtime -- this is the answer to
 * "can this person hand somebody else a password", and that answer should
 * be checkable on its own.
 */

/**
 * Roles that are allowed to provision a new account, and which roles each
 * of them is permitted to create. Kept explicit (not "any staff can
 * create any role") so, e.g., a Registrar account can never mint itself a
 * Director account even if the client were compromised.
 */
export const PROVISIONING_MATRIX: Record<string, string[]> = {
  // The Owner stands up a new school's leadership: a Director to run it
  // and an Admin to do the day-to-day setup, without having to sign in as
  // the Director first just to create the Admin.
  owner: ["director", "admin"],

  // The Director does not appear as a caller. Creating an account is an
  // operational act -- it hands somebody a password and a role -- and the
  // Director supervises rather than operates (see the note at the top of
  // firestore.rules). The Director is a *target* role the Admin may
  // create, which is a different thing: filling a vacant post is
  // operations, and the Director having no way to mint their own
  // operator is the separation the rules header describes.
  //
  // The Admin creates every role a school has. "admin" is on this list on
  // purpose: an admin office is a department, not a person, and the
  // version without it meant a school whose one Admin left, went on
  // leave, or lost their phone had to come back to the vendor for
  // another one -- the Owner being the only other account that could
  // mint an Admin. That is a support ticket standing in for a
  // permission, and every day it takes is a day nobody at the school can
  // enrol a student or run payroll.
  //
  // What stays out of reach is "owner", and it is the only thing.
  admin: [
    "director",
    "principal",
    "admin",
    "registrar",
    "faculty",
    "staff",
    "guidance",
    "student",
    "parent",
  ],

  registrar: ["student", "parent"],
};

/**
 * Roles no caller may ever create, whatever the matrix says.
 *
 * "owner" appears in no row above, and this makes that explicit rather
 * than incidental. There is exactly one Owner and it is established once,
 * by bootstrapOwner, against a server-side email -- never minted through
 * the ordinary provisioning path. If a future edit adds "owner" to some
 * row by accident, this still refuses.
 */
export const UNPROVISIONABLE_ROLES = ["owner"];

/** Why a provisioning attempt was refused, or null if it was not. */
export interface ProvisioningRefusal {
  /** "unprovisionable" is about the target alone; "not-permitted" is
   * about this caller reaching for that target. */
  kind: "unprovisionable" | "not-permitted";
  message: string;
}

/**
 * Decides whether [callerRole] may create a [targetRole] account.
 *
 * Returns null when it may. The two refusals are kept distinct because
 * they tell the caller different things: one says the role cannot be
 * created here by anybody, the other says it cannot be created by them.
 */
export function refuseProvisioning(
  callerRole: string,
  targetRole: string
): ProvisioningRefusal | null {
  if (UNPROVISIONABLE_ROLES.includes(targetRole)) {
    return {
      kind: "unprovisionable",
      message: `A ${targetRole} account cannot be created this way.`,
    };
  }

  const allowed = PROVISIONING_MATRIX[callerRole];
  if (!allowed || !allowed.includes(targetRole)) {
    return {
      kind: "not-permitted",
      message: `Your role (${callerRole}) cannot create a ${targetRole} account.`,
    };
  }

  return null;
}
