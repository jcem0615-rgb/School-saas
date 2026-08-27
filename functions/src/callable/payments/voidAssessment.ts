import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {reverseAssessment} from "../../shared/payments/balanceMath";

interface VoidAssessmentData {
  schoolId: string;
  assessmentId: string;
  reason: string;
}

const ALLOWED_ROLES = ["director", "admin", "registrar"];

/**
 * Reverses an assessment, putting the balance back.
 *
 * Voiding, not deleting, and the distinction is the point. The balance
 * moved when the assessment was made; a record that could simply
 * disappear would leave a figure nobody could account for and an
 * itemised list that no longer adds up to it. This leaves both the
 * charge and its reversal on the student's record, which is what lets
 * anyone reconstruct how the balance got where it is.
 *
 * `firestore.rules` refuses every client update and delete on
 * `assessments`, so this callable is the only thing that can mark one
 * voided -- the same posture as the document release log, for the same
 * reason.
 */
export const voidAssessment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<VoidAssessmentData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {schoolId, assessmentId, reason} = request.data;
    if (!schoolId || !assessmentId) {
      throw new HttpsError("invalid-argument", "Missing assessment details.");
    }
    // A reversal with no reason is the thing an auditor asks about, so
    // it is refused rather than stored blank.
    if (!reason || !reason.trim()) {
      throw new HttpsError("invalid-argument", "A reason is required when voiding an assessment.");
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();
    const assessmentRef = db.doc(FirestorePaths.assessmentDoc(schoolId, assessmentId));

    const result = await db.runTransaction(async (tx) => {
      const assessmentSnap = await tx.get(assessmentRef);
      if (!assessmentSnap.exists) {
        throw new HttpsError("not-found", "Assessment not found.");
      }
      const assessment = assessmentSnap.data()!;

      // Read inside the transaction: two cashiers voiding the same
      // assessment at once would otherwise each reverse it, taking the
      // balance down twice for one charge.
      if (assessment.voidedAt) {
        throw new HttpsError("failed-precondition", "That assessment has already been voided.");
      }

      const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, assessment.studentId as string));
      const studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) {
        throw new HttpsError("not-found", "Student record not found.");
      }
      const previousBalance = (studentSnap.data()?.balance as number) ?? 0;
      const total = (assessment.total as number) ?? 0;
      const newBalance = reverseAssessment(previousBalance, total);

      tx.update(assessmentRef, {
        voidedAt: admin.firestore.FieldValue.serverTimestamp(),
        voidedBy: request.auth!.uid,
        voidedByName: (request.auth!.token.name as string) ?? "Unknown",
        voidReason: reason.trim(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(studentRef, {
        balance: newBalance,
        updatedBy: request.auth!.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        studentId: assessment.studentId as string,
        total,
        previousBalance,
        newBalance,
      };
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "",
      module: "payments",
      action: "void_assessment",
      targetCollection: FirestorePaths.assessments(schoolId),
      targetId: assessmentId,
      previousValue: {balance: result.previousBalance},
      newValue: {balance: result.newBalance, reversed: result.total},
      success: true,
      remarks: reason.trim(),
    });

    return {
      assessmentId,
      studentId: result.studentId,
      previousBalance: result.previousBalance,
      balance: result.newBalance,
    };
  }
);
