import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {applyRefund} from "../../shared/payments/balanceMath";

interface RecordRefundData {
  schoolId: string;
  paymentId: string;
  reason: string;
}

// Refunds are more consequential than collecting a payment (money leaves,
// and a completed transaction is being reversed) -- restricted to
// Director/Admin only, deliberately excluding Registrar even though
// Registrar can collect payments. A cashier who can both take and refund
// money unilaterally is a classic embezzlement vector; requiring a
// different, more senior role to reverse a transaction is a real control,
// not just a formality.
const REFUND_ALLOWED_ROLES = ["director", "admin"];

export const recordRefund = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordRefundData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, REFUND_ALLOWED_ROLES);

    const {schoolId, paymentId, reason} = request.data;
    if (!schoolId || !paymentId || !reason || !reason.trim()) {
      throw new HttpsError("invalid-argument", "schoolId, paymentId, and reason are required.");
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();
    const originalRef = db.doc(FirestorePaths.paymentDoc(schoolId, paymentId));
    const originalSnap = await originalRef.get();
    if (!originalSnap.exists) {
      throw new HttpsError("not-found", "Original payment not found.");
    }
    const original = originalSnap.data()!;
    if (original.status === "refunded") {
      throw new HttpsError("failed-precondition", "This payment has already been refunded.");
    }

    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, original.studentId as string));
    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      throw new HttpsError("not-found", "Student record not found.");
    }
    const student = studentSnap.data()!;

    const refundAmount = original.amount as number;
    const newBalance = applyRefund((student.balance as number) ?? 0, refundAmount);
    const refundRef = db.collection(FirestorePaths.payments(schoolId)).doc();

    await db.runTransaction(async (tx) => {
      tx.update(originalRef, {
        status: "refunded",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
      tx.set(refundRef, {
        id: refundRef.id,
        schoolId,
        studentId: original.studentId,
        amount: -refundAmount, // negative: money moving back out
        method: original.method,
        referenceNumber: original.referenceNumber ?? null,
        receiptNumber: `${original.receiptNumber}-R`,
        collectedBy: request.auth!.uid,
        collectedByName: (request.auth!.token.name as string) ?? "Unknown",
        purpose: original.purpose,
        status: "completed",
        refundOf: paymentId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: request.auth!.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
        deletedAt: null,
        deletedBy: null,
        isDeleted: false,
      });
      tx.update(studentRef, {
        balance: newBalance,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "payments",
      action: "payment_refunded",
      targetCollection: FirestorePaths.payments(schoolId),
      targetId: paymentId,
      previousValue: {status: "completed"},
      newValue: {status: "refunded", refundId: refundRef.id},
      success: true,
      remarks: reason.trim(),
    });

    return {refundId: refundRef.id, newBalance};
  }
);
