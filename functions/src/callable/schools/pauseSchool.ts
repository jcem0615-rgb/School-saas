import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface PauseSchoolData {
  schoolId: string;
  reason: string;
}

export const pauseSchool = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<PauseSchoolData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ["owner"]);

    const {schoolId, reason} = request.data;
    if (!schoolId || !reason || !reason.trim()) {
      throw new HttpsError("invalid-argument", "schoolId and reason are required.");
    }

    const subscriptionRef = admin.firestore().doc(FirestorePaths.platformSubscriptionDoc(schoolId));
    const snap = await subscriptionRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "School subscription not found.");
    }
    const before = snap.data();

    // autoSuspendEnabled: false marks this as a manual pause, so
    // gracePeriodCheckJob will never touch or "helpfully" resume it.
    await subscriptionRef.update({
      currentStatus: "suspended",
      suspendedAt: admin.firestore.FieldValue.serverTimestamp(),
      autoSuspendEnabled: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Owner",
      module: "subscription",
      action: "manual_pause",
      targetCollection: FirestorePaths.platformSubscriptions,
      targetId: schoolId,
      previousValue: {currentStatus: before?.currentStatus},
      newValue: {currentStatus: "suspended"},
      success: true,
      remarks: reason.trim(),
    });

    return {success: true};
  }
);
