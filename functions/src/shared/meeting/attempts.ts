import * as admin from "firebase-admin";
import {HttpsError} from "firebase-functions/v2/https";
import {FirestorePaths} from "../firestore-paths";

/**
 * How many wrong codes before the door stops answering.
 *
 * Generous enough to survive a class mishearing the teacher twice and a
 * phone keyboard doing something unhelpful; short enough that nobody
 * works through a meaningful share of a thirty-two character alphabet.
 */
export const MAX_WRONG = 8;

/** How long a locked-out person waits. One lesson is fifty minutes. */
export const LOCKOUT_MINUTES = 10;

/**
 * Counts wrong passcodes, per person per lesson.
 *
 * A lock with unlimited attempts is a suggestion. Eight characters from
 * thirty-two is a thousand billion codes, so this is not what makes
 * guessing impractical -- but a door that will answer for ever is worth
 * standing at, and a door that stops answering after eight is not.
 *
 * Per person and per lesson, deliberately. Locking the *lesson* after
 * eight wrong guesses would hand any pupil in the class a way to shut
 * the rest of them out of it, which is a worse problem than the one
 * being solved.
 *
 * The counter lives in its own collection that firestore.rules denies
 * to everybody: a client that could read it would learn how many
 * guesses are left, and a client that could write it could reset them.
 */
export async function refuseIfLockedOut(
  schoolId: string,
  sessionId: string,
  uid: string,
  now: Date
): Promise<void> {
  const snap = await admin
    .firestore()
    .doc(FirestorePaths.meetingAttemptDoc(schoolId, sessionId, uid))
    .get();
  if (!snap.exists) return;

  const data = snap.data() ?? {};
  const wrong = typeof data.wrong === "number" ? data.wrong : 0;
  if (wrong < MAX_WRONG) return;

  const since = (data.lastWrongAt as admin.firestore.Timestamp | undefined)?.toDate();
  if (since && now.getTime() - since.getTime() > LOCKOUT_MINUTES * 60_000) {
    return;
  }

  throw new HttpsError(
    "resource-exhausted",
    `Too many wrong codes. Wait ${LOCKOUT_MINUTES} minutes, or ask your ` +
      "teacher to read the code out again."
  );
}

/** Records a wrong code. */
export async function recordWrongPasscode(
  schoolId: string,
  sessionId: string,
  uid: string
): Promise<void> {
  const ref = admin
    .firestore()
    .doc(FirestorePaths.meetingAttemptDoc(schoolId, sessionId, uid));
  await ref.set(
    {
      schoolId,
      sessionId,
      uid,
      wrong: admin.firestore.FieldValue.increment(1),
      lastWrongAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

/**
 * Forgets the wrong ones, once the right code arrives.
 *
 * Otherwise a child who mistyped the code seven times this morning
 * starts the afternoon one keystroke from being locked out of a lesson
 * they are entitled to be in.
 */
export async function forgetWrongPasscodes(
  schoolId: string,
  sessionId: string,
  uid: string
): Promise<void> {
  await admin
    .firestore()
    .doc(FirestorePaths.meetingAttemptDoc(schoolId, sessionId, uid))
    .delete()
    .catch(() => undefined);
}
