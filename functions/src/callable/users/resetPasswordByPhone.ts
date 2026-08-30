import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {normalizePhone, resolvePhoneAccount} from "../../shared/auth/phone";

interface ResetPasswordByPhoneData {
  /**
   * Optional, and usually absent.
   *
   * Somebody who cannot sign in does not know their school's internal
   * id, and asking them for it would make recovery impossible for the
   * people it exists for. Left out, every school on the platform is
   * searched; passed, only that one is.
   */
  schoolId?: string;
  newPassword: string;
}

/**
 * A ceiling on how much recovery is allowed to read.
 *
 * Password recovery is rare and a platform of this size is small, so
 * scanning every school is affordable. It stops being affordable at some
 * point, and a limit that refuses loudly is better than one that
 * silently costs a fortune on the day the platform grows.
 */
const MAX_SCHOOLS_SEARCHED = 200;

/** Firebase Auth's own floor. Stated here so the refusal is ours. */
const MIN_PASSWORD_LENGTH = 8;

/**
 * Sets a new password for the account a verified phone number belongs to.
 *
 * The proof of identity is the SIM. The caller reaches this having
 * signed in through Firebase Phone Auth, which means they received an
 * SMS code on that handset -- so `request.auth.token.phone_number` is a
 * number Firebase itself verified, not one the client typed. This then
 * asks a single question: which account did the school write that number
 * against?
 *
 * Exactly one, or nothing happens. Two accounts sharing a number is not
 * a tie to break by picking the first: whichever it chose would be a
 * password reset the other person never asked for.
 *
 * The phone session the caller is holding is *not* the account. They are
 * signed out of it afterwards and sign in normally with the password
 * they just set -- which is also why every existing session on the
 * recovered account is revoked here: somebody recovering an account is
 * often doing it because somebody else has it.
 */
export const resetPasswordByPhone = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<ResetPasswordByPhoneData>) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Verify your phone number first.");
    }

    // Present only for a session established by phone sign-in. A caller
    // signed in any other way -- including one signed in as somebody
    // else entirely -- has no phone_number on their token and stops
    // here.
    const verifiedPhone = normalizePhone(request.auth.token.phone_number);
    if (!verifiedPhone) {
      throw new HttpsError(
        "failed-precondition",
        "This can only be used right after verifying your phone number."
      );
    }

    const {schoolId, newPassword} =
      request.data ?? ({} as ResetPasswordByPhoneData);
    if (typeof newPassword !== "string" || newPassword.length < MIN_PASSWORD_LENGTH) {
      throw new HttpsError(
        "invalid-argument",
        `Choose a password of at least ${MIN_PASSWORD_LENGTH} characters.`
      );
    }

    const db = admin.firestore();
    const schoolIds = schoolId ? [schoolId] : await allSchoolIds(db);

    // Every user in each school, filtered in memory rather than queried
    // on `phone`. The stored numbers are in three different formats, so
    // an equality query would miss the two that are not written the way
    // the handset reports them -- which is most of them.
    //
    // Candidates are gathered across all the searched schools before
    // being resolved, so a number registered at two schools comes out as
    // ambiguous rather than as whichever school was read first.
    const candidates: {uid: string; schoolId: string; phone: unknown;
      role?: string; status?: string; isDeleted?: boolean}[] = [];
    for (const id of schoolIds) {
      const usersSnap = await db.collection(FirestorePaths.users(id)).get();
      for (const doc of usersSnap.docs) {
        candidates.push({
          uid: doc.id,
          schoolId: id,
          phone: doc.data().phone,
          role: doc.data().role as string | undefined,
          status: doc.data().status as string | undefined,
          isDeleted: doc.data().isDeleted as boolean | undefined,
        });
      }
    }

    const match = resolvePhoneAccount(candidates, verifiedPhone);

    switch (match.outcome) {
      case "none":
        // Deliberately says so plainly rather than pretending to have
        // sent something. A recovery that silently does nothing leaves
        // somebody waiting for a text that is never coming; and the
        // number is already proven to be theirs, so "no account here"
        // discloses nothing they could not learn by trying to sign in.
        throw new HttpsError(
          "not-found",
          "No active account at this school is registered to that number. " +
            "Ask the office to check the number on your record."
        );
      case "ambiguous":
        throw new HttpsError(
          "failed-precondition",
          "That number is registered to more than one account here, so it " +
            "cannot be used to reset a password. Please contact the office."
        );
      case "refused":
        throw new HttpsError(
          "permission-denied",
          "That account cannot be recovered by phone."
        );
      case "matched":
        break;
    }

    const uid = match.uid;
    const foundIn = candidates.find((c) => c.uid === uid)!.schoolId;
    await admin.auth().updateUser(uid, {password: newPassword});
    // Somebody recovering an account is often doing it because somebody
    // else has it. Every other session ends here.
    await admin.auth().revokeRefreshTokens(uid);

    await db.doc(FirestorePaths.userDoc(foundIn, uid)).update({
      // They chose this password themselves, so there is nothing to
      // force them to change on the way in.
      mustChangePassword: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    });

    const claims = (await admin.auth().getUser(uid)).customClaims ?? {};
    await admin.auth().setCustomUserClaims(uid, {
      ...claims,
      mustChangePassword: false,
    });

    await writeAuditLog({
      schoolId: foundIn,
      userId: uid,
      userRole: (claims.role as string) ?? "unknown",
      userName: "Phone recovery",
      module: "auth",
      action: "password_reset_by_phone",
      targetCollection: FirestorePaths.users(foundIn),
      targetId: uid,
      // The number is not written into the log. It is on the user
      // record already, and an audit trail is read by more people than
      // the record is.
      newValue: {method: "phone_otp"},
      success: true,
    });

    return {ok: true};
  }
);

/**
 * Every school on the platform.
 *
 * Read from the platform registry, which no tenant client can see. The
 * cap is not a performance tuning knob -- it is the point at which this
 * approach stops being the right one, and refusing is better than
 * quietly reading a hundred thousand user documents to answer one
 * password reset.
 */
async function allSchoolIds(db: FirebaseFirestore.Firestore): Promise<string[]> {
  const snap = await db.collection(FirestorePaths.platformSchools).get();
  if (snap.size > MAX_SCHOOLS_SEARCHED) {
    throw new HttpsError(
      "failed-precondition",
      "Password recovery by phone needs your school to be selected. " +
        "Please contact your school office."
    );
  }
  return snap.docs.map((doc) => doc.id);
}
