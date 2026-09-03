/**
 * The email address and mobile number on a student's record.
 *
 * Both are optional -- a Grade 1 pupil has neither, and a school that
 * cannot register that child until somebody invents an address for them
 * will invent one. But when either IS given it has to be usable, because
 * of what each one is for:
 *
 *   * the email becomes the account the student signs in with, so an
 *     address with a typo in it is an account nobody can ever reach;
 *   * the mobile number is what resetPasswordByPhone matches against, so
 *     a number stored in a shape normalizePhone cannot read is a number
 *     that recovers nothing.
 *
 * Rejecting a bad one at registration is the only cheap moment. After
 * that it is discovered by a family who cannot get in, on the day they
 * need to.
 */

import {normalizePhone} from "../auth/phone";

/**
 * The same shape the client's Validators.email accepts, deliberately.
 *
 * The `(\.[\w-]+)*` group is what allows multi-label domains -- without
 * it the pattern rejects every `*.edu.ph` address, which is most school
 * addresses in this country and therefore most of this product's users.
 * A server that refused what the form accepted would be a bug reported as
 * "it says invalid but it looks fine".
 */
const EMAIL = /^[\w.+-]+@[\w-]+(\.[\w-]+)*\.[a-zA-Z]{2,}$/;

/**
 * Trimmed and lower-cased, or "" when there is nothing usable.
 *
 * Lower-cased because the local part of an address is case-sensitive in
 * the standard and case-insensitive at every mail provider anybody here
 * actually uses. Storing what was typed means `Juan@x.edu.ph` and
 * `juan@x.edu.ph` are two accounts, and the second person to be
 * registered is told the address is already taken by somebody who,
 * as far as the office is concerned, is them.
 */
export function normalizeEmail(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const trimmed = raw.trim().toLowerCase();
  return EMAIL.test(trimmed) ? trimmed : "";
}

/** Whether this is an address an account could be created against. */
export function isValidEmail(raw: unknown): boolean {
  return normalizeEmail(raw) !== "";
}

export interface ContactDetails {
  email: string | null;
  phone: string | null;
}

export class ContactDetailsError extends Error {}

/**
 * Validates the pair, returning what should be written to the record.
 *
 * An empty or absent value is null rather than "": a record with no
 * number on it should read as having none, not as having a blank one.
 * The distinction matters at the far end -- resolvePhoneAccount treats a
 * blank number as matching nothing, and it should stay that way, but
 * "students with no number on file" is a list a school genuinely wants
 * and cannot build from empty strings mixed with nulls.
 *
 * The phone is stored as it was typed, not normalised. Normalising is a
 * lossy, matching-time concern -- `+63 917 555 0100` is what the office
 * will read out loud to a parent, and `639175550100` is not. What is
 * checked here is that normalizePhone CAN read it, so the stored form and
 * the matched form can never disagree.
 */
export function validateContactDetails(input: {
  email?: unknown;
  phone?: unknown;
}): ContactDetails {
  const rawEmail = typeof input.email === "string" ? input.email.trim() : "";
  const rawPhone = typeof input.phone === "string" ? input.phone.trim() : "";

  let email: string | null = null;
  if (rawEmail) {
    email = normalizeEmail(rawEmail);
    if (!email) {
      throw new ContactDetailsError(
        `"${rawEmail}" is not a valid email address. This becomes the ` +
          "student's sign-in, so it has to be one they can receive mail at."
      );
    }
  }

  let phone: string | null = null;
  if (rawPhone) {
    if (!normalizePhone(rawPhone)) {
      throw new ContactDetailsError(
        `"${rawPhone}" is not a mobile number this system can read. Use ` +
          "09171234567, +639171234567, or 9171234567."
      );
    }
    phone = rawPhone;
  }

  return {email, phone};
}
