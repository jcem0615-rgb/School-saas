import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {applyPayment, formatReceiptNumber} from "../../shared/payments/balanceMath";

interface RecordPaymentData {
  schoolId: string;
  studentId: string;
  amount: number;
  method: "cash" | "gcash" | "bank_transfer" | "online";
  referenceNumber?: string;
  purpose: "tuition" | "misc_fee" | "other";
}

// Roles that may collect/record a payment. Faculty/Staff/Guidance have no
// business handling money -- keeping this list tight limits blast radius
// if any one account is compromised.
const COLLECTOR_ALLOWED_ROLES = ["director", "admin", "registrar"];

/**
 * Payments are recorded by collectors only.
 *
 * Students and parents deliberately cannot reach this. They file a
 * paymentSubmission instead, and decidePaymentSubmission creates the
 * Payment once a cashier has verified the reference against the school's
 * e-wallet. Letting them call this directly would let anyone credit their
 * own balance by asserting they had paid, which is exactly what the
 * review step exists to prevent.
 */
async function authorizePayer(
  callerRole: string
): Promise<void> {
  if (!COLLECTOR_ALLOWED_ROLES.includes(callerRole)) {
    throw new HttpsError(
      "permission-denied",
      "Only a cashier can record a payment. Submit it for review instead."
    );
  }
}

export const recordPayment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordPaymentData>) => {
    const callerClaims = requireCallerClaims(request);

    const {schoolId, studentId, amount, method, referenceNumber, purpose} = request.data;
    if (!schoolId || !studentId || !amount || amount <= 0 || !method || !purpose) {
      throw new HttpsError("invalid-argument", "Missing or invalid payment details.");
    }
    requireSameSchool(callerClaims, schoolId);
    if ((method === "gcash" || method === "bank_transfer") && !referenceNumber) {
      throw new HttpsError("invalid-argument", "A reference number is required for this payment method.");
    }

    const db = admin.firestore();
    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, studentId));
    const studentSnap = await studentRef.get();
    if (!studentSnap.exists) {
      throw new HttpsError("not-found", "Student record not found.");
    }
    const student = studentSnap.data()!;

    // Authorization needs the student record (to check ownership/linkage),
    // so it happens here rather than at the top of the handler.
    await authorizePayer(callerClaims.role);

    const sequence = await getNextSequence(schoolId, "receiptNumber");
    const receiptNumber = formatReceiptNumber(sequence, new Date().getFullYear());

    const paymentRef = db.collection(FirestorePaths.payments(schoolId)).doc();
    const newBalance = applyPayment((student.balance as number) ?? 0, amount);

    await db.runTransaction(async (tx) => {
      tx.set(paymentRef, {
        id: paymentRef.id,
        schoolId,
        studentId,
        amount,
        method,
        referenceNumber: referenceNumber ?? null,
        receiptNumber,
        collectedBy: request.auth!.uid,
        collectedByName: (request.auth!.token.name as string) ?? "Unknown",
        purpose,
        status: "completed",
        refundOf: null,
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
      action: "payment_recorded",
      targetCollection: FirestorePaths.payments(schoolId),
      targetId: paymentRef.id,
      newValue: {studentId, amount, method, receiptNumber},
      success: true,
    });

    return {
      paymentId: paymentRef.id,
      receiptNumber,
      newBalance,
    };
  }
);
