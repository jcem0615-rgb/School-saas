import {randomBytes} from "crypto";

/**
 * The name of the video room a class meets in.
 *
 * A Jitsi room is created by the first person to open its URL, and on a
 * shared deployment anybody who knows the name is in the room. There is
 * no password step between knowing it and being in a lesson with forty
 * children. So the name is the secret, and everything here exists to
 * keep it one.
 *
 * ## It carries nothing about the class
 *
 * The obvious name is the one you would write by hand --
 * `logicclass-school_a-grade10-rizal-math-2026-09-23`. Two things are
 * wrong with it, and the second is the serious one:
 *
 *  * It is **guessable**. A name built from the school, the section and
 *    the date can be typed by anyone who knows those three things, which
 *    at a school is everybody. An expelled student, a stranger who read
 *    a timetable on a noticeboard -- both are one URL away from a live
 *    class.
 *  * It is **readable**. The room name is in the address bar of every
 *    participant and in whatever they paste into a chat. A name naming
 *    the school, the section and the subject discloses all three to
 *    anyone who ever sees the link, which is the opposite of what a
 *    tenant boundary is for.
 *
 * So the name is random and says nothing. What class it belongs to is
 * recorded where it should be -- on the session document, behind the
 * rules -- and not in the identifier itself.
 *
 * ## It is per session, not per class
 *
 * A new one each time a lesson is taken online. Reusing a room across
 * every Monday would mean last term's leaver can still walk into this
 * morning's class, forever, and nothing about their leaving would have
 * closed the door.
 */

/**
 * 15 bytes -> 24 base64url characters, ~120 bits.
 *
 * Far past guessing, and short enough to read out over a bad phone line
 * to a parent whose child cannot get in -- which is a thing that will
 * happen on the first morning a school does this.
 */
const ROOM_BYTES = 15;

/** Lower-case alphanumeric only: safest across Jitsi deployments. */
const ROOM_PATTERN = /^lc-[a-z0-9]{20,40}$/;

/**
 * A fresh room name.
 *
 * Prefixed so a name is recognisable as this app's in a server log
 * without the rest of it meaning anything.
 */
export function newMeetingRoom(): string {
  const raw = randomBytes(ROOM_BYTES)
    .toString("base64")
    .replace(/[^a-zA-Z0-9]/g, "")
    .toLowerCase();
  // base64 of 15 bytes is 20 chars with no padding and no more than a
  // couple of non-alphanumerics, but a short draw is still possible --
  // top it up rather than return something below the entropy this
  // promises.
  const padded = raw.length >= 20 ? raw : (raw + randomBytes(ROOM_BYTES).toString("hex"));
  return `lc-${padded.slice(0, 24)}`;
}

/**
 * Whether a stored value is one of ours.
 *
 * Checked on the way *out* as well as in: a room name that reached the
 * document by some other route is one this app did not generate, and
 * sending a class to it is sending them somewhere unknown.
 */
export function isMeetingRoom(value: unknown): value is string {
  return typeof value === "string" && ROOM_PATTERN.test(value);
}
