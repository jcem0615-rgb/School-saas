import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

/**
 * Called by a user immediately after they successfully change their own
 * password (voluntary or forced). Clears `mustChangePassword` on both the
 * custom claim and the Firestore profile doc.
 *
 * Deliberately NOT a client-writable Firestore field: if the client could
 * clear this flag directly, a compromised device could skip the forced
 * password rotation entirely by just writing `false` to its own doc.
 */
export const clearForcePasswordChangeFlag = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<Record<string, never>>) => {
    const callerClaims = requireCallerClaims(request);
    const uid = request.auth!.uid;

    if (!callerClaims.schoolId) {
      throw new HttpsError("failed-precondition", "This action is not applicable to this account type.");
    }

    await admin.auth().setCustomUserClaims(uid, {
      schoolId: callerClaims.schoolId,
      role: callerClaims.role,
      status: callerClaims.status,
      mustChangePassword: false,
    });

    const userRef = admin.firestore().doc(FirestorePaths.userDoc(callerClaims.schoolId, uid));
    await userRef.update({
      mustChangePassword: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    });

    await writeAuditLog({
      schoolId: callerClaims.schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "users",
      action: "password_change_self",
      targetCollection: FirestorePaths.users(callerClaims.schoolId),
      targetId: uid,
      success: true,
    });

    return {success: true};
  }
);
