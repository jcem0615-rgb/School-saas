import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {setUserClaims} from "../../shared/auth/claims";
import {writeOwnerAuditLog} from "../../shared/audit/writeOwnerAuditLog";

/**
 * Establishes the single platform Owner, once.
 *
 * Every other account in the system is created by someone who already has
 * an account. The Owner is the account that has nobody above it, so it
 * cannot be provisioned the ordinary way -- provisionUser refuses the
 * owner role outright. This is the one door, and it is built to be walked
 * through exactly once:
 *
 *   1. The caller must already be signed in with Firebase Auth. This
 *      function grants a role; it does not create credentials, so there
 *      is no way to use it to mint an account.
 *   2. Their verified email must equal OWNER_EMAIL, which is set in the
 *      function's environment, server side. Nothing the client sends is
 *      trusted here.
 *   3. No owner may exist yet. Once one does, this function refuses
 *      everyone, including the configured email -- so it cannot be
 *      replayed to hand the role to a second account, and a stolen
 *      session cannot re-run it.
 *
 * Deploy with the email set, e.g.
 *
 *     firebase functions:secrets:set OWNER_EMAIL
 *
 * or as an environment variable in .env for the functions codebase.
 */

/** Where the claim lives once granted. Also the flag that closes the door. */
const OWNER_MARKER_DOC = "platform_config/owner";

export const bootstrapOwner = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<void>) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in with the owner account first, then run this once."
      );
    }

    const configured = (process.env.OWNER_EMAIL ?? "").trim().toLowerCase();
    if (!configured) {
      // Refusing is the safe failure. An unset OWNER_EMAIL with a
      // permissive fallback would make this an open door to the highest
      // privilege in the system.
      throw new HttpsError(
        "failed-precondition",
        "OWNER_EMAIL is not configured for this deployment."
      );
    }

    const email = (request.auth.token.email ?? "").trim().toLowerCase();
    const emailVerified = request.auth.token.email_verified === true;
    if (!email || email !== configured) {
      throw new HttpsError("permission-denied", "This account cannot be the owner.");
    }
    if (!emailVerified) {
      // Without this, anyone who can sign up with an unverified address
      // could claim the configured one on a provider that permits it.
      throw new HttpsError(
        "failed-precondition",
        "Verify the owner email address before claiming the role."
      );
    }

    const db = admin.firestore();
    const markerRef = db.doc(OWNER_MARKER_DOC);

    // The check and the write are one transaction. Two callers racing
    // would otherwise both read "no owner" and both be granted it.
    const uid = request.auth.uid;
    await db.runTransaction(async (tx) => {
      const existing = await tx.get(markerRef);
      if (existing.exists) {
        throw new HttpsError(
          "already-exists",
          "This platform already has an owner."
        );
      }
      tx.set(markerRef, {
        uid,
        email,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await setUserClaims(uid, {
      role: "owner",
      status: "active",
      mustChangePassword: false,
      // No schoolId: the Owner is platform-level and belongs to no tenant.
    });

    // Platform-level, not the tenant log: there is no school to file this
    // under, and this is the entry that says how the highest privilege in
    // the system came to exist.
    await writeOwnerAuditLog({
      actorUid: uid,
      actorEmail: email,
      action: "owner.bootstrapped",
      targetType: "user",
      targetId: uid,
    });

    return {
      ok: true,
      // The claim is baked into the ID token, which the client is still
      // holding an older copy of.
      message: "Owner role granted. Sign out and back in to refresh your session.",
    };
  }
);
