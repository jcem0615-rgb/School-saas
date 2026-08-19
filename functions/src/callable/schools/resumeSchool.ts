import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface ResumeSchoolData {
  schoolId: string;
}

export const resumeSchool = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<ResumeSchoolData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ["owner"]);

    const {schoolId} = request.data;
    if (!schoolId) {
      throw new HttpsError("invalid-argument", "schoolId is required.");
    }

    const subscriptionRef = admin.firestore().doc(FirestorePaths.platformSubscriptionDoc(schoolId));
    const snap = await subscriptionRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "School subscription not found.");
    }
    const before = snap.data();

    // Reactivation is immediate per spec -- no waiting for the next
    // billing cycle. Grace period markers are cleared so a fresh overdue
    // cycle (if any) starts clean rather than instantly re-triggering.
    await subscriptionRef.update({
      currentStatus: "active",
      suspendedAt: null,
      gracePeriodStartedAt: null,
      autoSuspendEnabled: true,
      currentCycleStart: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Owner",
      module: "subscription",
      action: "resume",
      targetCollection: FirestorePaths.platformSubscriptions,
      targetId: schoolId,
      previousValue: {currentStatus: before?.currentStatus},
      newValue: {currentStatus: "active"},
      success: true,
    });

    return {success: true};
  }
);
