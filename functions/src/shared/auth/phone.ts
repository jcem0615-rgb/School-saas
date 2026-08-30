/**
 * Matching a phone number somebody typed against the one the school
 * wrote down.
 *
 * These never agree on format. A registrar types `0917 555 0100`, a
 * parent's handset reports `+639175550100`, somebody else writes
 * `(0917) 555-0100`, and all three are the same phone. Comparing them as
 * strings means a family locked out of their account by a space.
 *
 * Pure and separately tested because this decides who is allowed to
 * reset somebody's password, and "close enough" is not a standard this
 * can be held to: too loose and one family's number recovers another's
 * account.
 */

/** The country this platform serves. Philippine numbers are +63. */
const COUNTRY_CODE = "63";

/**
 * Reduces a number to digits in international form, or "" when there is
 * nothing usable.
 *
 * Deliberately conservative. Anything that does not look like a phone
 * number comes back empty, and an empty number matches nothing --
 * including another empty one.
 */
export function normalizePhone(raw: unknown): string {
  if (typeof raw !== "string") return "";
  const digits = raw.replace(/[^\d+]/g, "");
  if (!digits) return "";

  // +639175550100 -> 639175550100
  if (digits.startsWith("+")) {
    const rest = digits.slice(1);
    return /^\d{8,15}$/.test(rest) ? rest : "";
  }

  // 09175550100 -> 639175550100. A leading zero is the national trunk
  // prefix and is dropped when the country code goes on; keeping it
  // would make 09... and +639... two different numbers.
  if (digits.startsWith("0")) {
    const rest = digits.slice(1);
    return /^\d{8,14}$/.test(rest) ? `${COUNTRY_CODE}${rest}` : "";
  }

  // Already in country form.
  if (digits.startsWith(COUNTRY_CODE) && /^\d{10,15}$/.test(digits)) {
    return digits;
  }

  // A bare local number, no prefix at all: 9175550100.
  if (/^9\d{9}$/.test(digits)) return `${COUNTRY_CODE}${digits}`;

  return "";
}

/** Whether two numbers are the same phone, whatever they were typed as. */
export function samePhone(a: unknown, b: unknown): boolean {
  const left = normalizePhone(a);
  const right = normalizePhone(b);
  // An unusable number matches nothing, including another unusable one.
  // Otherwise every account with a blank phone would match every other.
  return left !== "" && left === right;
}

export interface PhoneCandidate {
  uid: string;
  phone?: unknown;
  role?: string;
  status?: string;
  isDeleted?: boolean;
}

export type PhoneMatch =
  | {outcome: "matched"; uid: string}
  | {outcome: "none"}
  | {outcome: "ambiguous"; count: number}
  | {outcome: "refused"; reason: "owner"};

/**
 * Which account, if any, a verified phone number recovers.
 *
 * Exactly one, or none. Two accounts sharing a number -- a parent who
 * also works at the school, a household with one handset -- is not a
 * tie to be broken by picking the first: whichever one this chose would
 * be a password reset the other person did not ask for. It refuses and
 * says so, and the office sorts it out.
 *
 * Suspended and soft-deleted accounts are not recoverable, and neither
 * is the platform Owner: a text message is not enough to take the
 * account that can reach every school on the platform.
 */
export function resolvePhoneAccount(candidates: PhoneCandidate[], phone: string): PhoneMatch {
  const wanted = normalizePhone(phone);
  if (!wanted) return {outcome: "none"};

  const matches = candidates.filter(
    (c) =>
      c.isDeleted !== true &&
      c.status === "active" &&
      samePhone(c.phone, wanted)
  );

  if (matches.length === 0) return {outcome: "none"};
  if (matches.length > 1) return {outcome: "ambiguous", count: matches.length};
  if (matches[0].role === "owner") return {outcome: "refused", reason: "owner"};
  return {outcome: "matched", uid: matches[0].uid};
}
