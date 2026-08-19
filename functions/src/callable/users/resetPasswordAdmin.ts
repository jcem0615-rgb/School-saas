import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface ResetPasswordData {
  schoolId: string;
  targetUserId: string;
}

// Roles permitted to force-reset another user's password within their school.
const RESET_ALLOWED_ROLES = ["owner", "director", "admin"];

export const resetPasswordAdmin = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<ResetPasswordData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, RESET_ALLOWED_ROLES);

    const {schoolId, targetUserId} = request.data;
    if (!schoolId || !targetUserId) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }
    if (callerClaims.role !== "owner") {
      requireSameSchool(callerClaims, schoolId);
    }

    const db = admin.firestore();
    const userRef = db.doc(FirestorePaths.userDoc(schoolId, targetUserId));
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      throw new HttpsError("not-found", "User not found.");
    }
    const userData = userSnap.data()!;

    // Flip mustChangePassword immediately so the account is locked into
    // the forced-change flow the next time it authenticates, regardless
    // of whether the reset-link email is ever opened.
    await admin.auth().setCustomUserClaims(targetUserId, {
      schoolId,
      role: userData.role,
      status: userData.status,
      mustChangePassword: true,
    });

    await userRef.update({
      mustChangePassword: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    const resetLink = await admin.auth().generatePasswordResetLink(userData.email);
    // TODO(integration): send resetLink via the transactional email
    // provider chosen in the Notifications module rather than returning
    // it to the client, once that module is built.

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "users",
      action: "password_reset_admin",
      targetCollection: FirestorePaths.users(schoolId),
      targetId: targetUserId,
      success: true,
      remarks: `Password reset initiated for ${userData.email}`,
    });

    return {resetLink};
  }
);
