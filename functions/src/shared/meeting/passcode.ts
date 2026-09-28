import {randomInt, timingSafeEqual} from "crypto";

/**
 * The code a teacher reads out before a lesson starts.
 *
 * ## Why there is one at all
 *
 * The register already decides who may join: a student reaches the room
 * through their own line in it and no other way. That answers "is this
 * child in this class". It does not answer "is this child the one
 * holding the phone" -- and in a school it often is not. Accounts are
 * shared between siblings, a tablet is passed around a house, a
 * password is written in the back of an exercise book.
 *
 * The passcode is the half of the answer the register cannot give. It
 * is said out loud at the start of the lesson, to the people who are
 * there, and it is never in the invitation link.
 *
 * ## Why this alphabet
 *
 * Crockford's base32: no I, no L, no O, no U. Three of them because a
 * code that is read aloud and typed by a ten-year-old must not turn on
 * whether a character was a one or an ell; the fourth because a random
 * code should not be able to spell something a teacher then has to read
 * to a class.
 *
 * Reading it back is forgiving in the same spirit -- I and L are taken
 * as 1, O as 0 -- so a child who hears "eye" and types I is let in
 * rather than told they got it wrong.
 */
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";

/**
 * Eight characters from thirty-two: about a thousand billion codes.
 *
 * Long enough that guessing is not a route in even without the limit on
 * attempts, short enough to say twice to a class over a bad connection.
 */
export const PASSCODE_LENGTH = 8;

/** A new code, from the system's own randomness rather than Math. */
export function newPasscode(): string {
  let code = "";
  for (let i = 0; i < PASSCODE_LENGTH; i++) {
    code += ALPHABET[randomInt(ALPHABET.length)];
  }
  return code;
}

/**
 * What somebody typed, as the code they meant.
 *
 * Spaces and dashes go, because a code shown as `A1B2-C3D4` will be
 * typed back with the dash. Case goes, because a phone keyboard
 * capitalises the first letter on its own.
 */
export function normalisePasscode(given: unknown): string {
  if (typeof given !== "string") return "";
  return given
    .toUpperCase()
    .replace(/[^0-9A-Z]/g, "")
    .replace(/[IL]/g, "1")
    .replace(/O/g, "0");
}

/** Whether a string could be a code this app made. */
export function isPasscode(given: unknown): boolean {
  const code = normalisePasscode(given);
  if (code.length !== PASSCODE_LENGTH) return false;
  return [...code].every((character) => ALPHABET.includes(character));
}

/**
 * Whether what was typed is the code that was set.
 *
 * Compared in constant time. The saving from an early exit is
 * microseconds and the cost is that the comparison tells a patient
 * caller how much of their guess was right, one character at a time.
 */
export function passcodeMatches(given: unknown, stored: unknown): boolean {
  const typed = normalisePasscode(given);
  const real = normalisePasscode(stored);
  if (!real) return false;
  if (typed.length !== real.length) return false;
  return timingSafeEqual(Buffer.from(typed), Buffer.from(real));
}

/** How it is shown to the teacher, and printed on an invitation. */
export function displayPasscode(code: string): string {
  const clean = normalisePasscode(code);
  if (clean.length !== PASSCODE_LENGTH) return clean;
  return `${clean.slice(0, 4)}-${clean.slice(4)}`;
}
