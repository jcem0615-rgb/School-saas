import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {applyPayment, formatReceiptNumber} from "../../shared/payments/balanceMath";

interface DecidePaymentSubmissionData {
  schoolId: string;
  submissionId: string;
  approve: boolean;
  remarks?: string;
}

// Same list that may collect a payment at the counter. Verifying an
// e-wallet transfer against the school's account is the same trust
// decision as accepting cash, so it carries the same role gate.
const REVIEWER_ROLES = ["director", "admin", "registrar"];

/**
 * Approves or rejects a family's claim that they paid online.
 *
 * This is the only path by which an online payment becomes money. A
 * student or parent can file a submission (Firestore rules let them, since
 * it moves nothing), but the balance does not change until a reviewer
 * confirms the reference number against the school's e-wallet and approves
 * here.
 *
 * Approval and the resulting Payment are written in one transaction, so a
 * submission can never end up marked approved without the payment that is
 * supposed to accompany it -- which would leave a family believing they
 * had been credited when they had not.
 */
export const decidePaymentSubmission = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<DecidePaymentSubmissionData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, REVIEWER_ROLES);

    const {schoolId, submissionId, approve, remarks} = request.data;
    if (!schoolId || !submissionId || typeof approve !== "boolean") {
      throw new HttpsError("invalid-argument", "Missing or invalid decision details.");
    }
    requireSameSchool(callerClaims, schoolId);

    if (!approve && !remarks?.trim()) {
      throw new HttpsError(
        "invalid-argument",
        "A reason is required when rejecting a payment submission."
      );
    }

    const db = admin.firestore();
    const submissionRef = db.doc(
      `${FirestorePaths.paymentSubmissions(schoolId)}/${submissionId}`
    );
    const submissionSnap = await submissionRef.get();
    if (!submissionSnap.exists) {
      throw new HttpsError("not-found", "Payment submission not found.");
    }
    const submission = submissionSnap.data()!;
    if (submission.status !== "pending") {
      throw new HttpsError("failed-precondition", "That submission has already been decided.");
    }

    const reviewerName = (request.auth!.token.name as string) ?? "";
    const decidedAt = admin.firestore.FieldValue.serverTimestamp();

    if (!approve) {
      await submissionRef.update({
        status: "rejected",
        reviewedByName: reviewerName,
        reviewedAt: decidedAt,
        decisionRemarks: remarks!.trim(),
        updatedBy: request.auth!.uid,
        updatedAt: decidedAt,
      });

      await writeAuditLog({
        schoolId,
        userId: request.auth!.uid,
        userRole: callerClaims.role,
        userName: reviewerName,
        module: "paymentSubmissions",
        action: "reject",
        targetCollection: FirestorePaths.paymentSubmissions(schoolId),
        targetId: submissionId,
        success: true,
        remarks: remarks!.trim(),
      });
      return {submissionId, approved: false};
    }

    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, submission.studentId as string));
    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      throw new HttpsError("not-found", "Student record not found.");
    }

    // Receipt numbers come from the same counter the counter-payment flow
    // uses, so an approved online payment is indistinguishable from a cash
    // one downstream -- same numbering, same history, same reports.
    const sequence = await getNextSequence(schoolId, "receiptNumber");
    const receiptNumber = formatReceiptNumber(sequence, new Date().getFullYear());
    const paymentRef = db.collection(FirestorePaths.payments(schoolId)).doc();
    const amount = submission.amount as number;

    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(studentRef);
      const newBalance = applyPayment((fresh.data()?.balance as number) ?? 0, amount);

      tx.set(paymentRef, {
        id: paymentRef.id,
        schoolId,
        studentId: submission.studentId,
        amount,
        method: submission.method,
        referenceNumber: submission.referenceNumber ?? null,
        receiptNumber,
        collectedByName: reviewerName,
        purpose: submission.purpose,
        status: "completed",
        refundOf: null,
        // Links the payment back to the claim it came from, so the trail
        // from "family said they paid" to "school recorded it" survives.
        submissionId,
        createdBy: request.auth!.uid,
        createdAt: decidedAt,
        updatedBy: request.auth!.uid,
        updatedAt: decidedAt,
        deletedAt: null,
        deletedBy: null,
        isDeleted: false,
      });

      tx.update(studentRef, {
        balance: newBalance,
        updatedBy: request.auth!.uid,
        updatedAt: decidedAt,
      });

      tx.update(submissionRef, {
        status: "approved",
        reviewedByName: reviewerName,
        reviewedAt: decidedAt,
        decisionRemarks: remarks?.trim() ?? null,
        resultingPaymentId: paymentRef.id,
        updatedBy: request.auth!.uid,
        updatedAt: decidedAt,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: reviewerName,
      module: "paymentSubmissions",
      action: "approve",
      targetCollection: FirestorePaths.paymentSubmissions(schoolId),
      targetId: submissionId,
      newValue: {amount, receiptNumber, paymentId: paymentRef.id},
      success: true,
      remarks: remarks?.trim(),
    });

    return {submissionId, approved: true, receiptNumber, paymentId: paymentRef.id};
  }
);
