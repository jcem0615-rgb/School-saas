import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface RecordPaymentData {
  schoolId: string;
  invoiceId: string;
  amount: number;
  method: "cash" | "gcash" | "bank_transfer" | "online";
  referenceNumber?: string;
}

export const recordManualPayment = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordPaymentData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ["owner"]);

    const {schoolId, invoiceId, amount, method, referenceNumber} = request.data;
    if (!schoolId || !invoiceId || !amount || amount <= 0 || !method) {
      throw new HttpsError("invalid-argument", "Missing or invalid payment details.");
    }
    if ((method === "gcash" || method === "bank_transfer") && !referenceNumber) {
      throw new HttpsError("invalid-argument", "A reference number is required for this payment method.");
    }

    const db = admin.firestore();
    const invoiceRef = db.doc(FirestorePaths.platformInvoiceDoc(invoiceId));
    const invoiceSnap = await invoiceRef.get();
    if (!invoiceSnap.exists) {
      throw new HttpsError("not-found", "Invoice not found.");
    }
    const invoice = invoiceSnap.data()!;
    if (invoice.schoolId !== schoolId) {
      throw new HttpsError("invalid-argument", "Invoice does not belong to the specified school.");
    }
    if (invoice.status === "paid") {
      throw new HttpsError("failed-precondition", "This invoice has already been paid.");
    }

    await invoiceRef.update({
      status: "paid",
      paidAt: admin.firestore.FieldValue.serverTimestamp(),
      paidAmount: amount,
      paymentMethod: method,
      paymentReference: referenceNumber ?? null,
      recordedBy: request.auth!.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    // Immediate reactivation after payment, per spec -- only if the
    // school's suspension was billing-related (autoSuspendEnabled true).
    // A manually-paused school (autoSuspendEnabled: false) stays paused
    // until the Owner explicitly resumes it; paying an invoice should not
    // silently override a deliberate manual pause for other reasons.
    const subscriptionRef = db.doc(FirestorePaths.platformSubscriptionDoc(schoolId));
    const subscriptionSnap = await subscriptionRef.get();
    const subscription = subscriptionSnap.data();
    if (
      subscription &&
      (subscription.currentStatus === "grace_period" ||
        (subscription.currentStatus === "suspended" && subscription.autoSuspendEnabled !== false))
    ) {
      await subscriptionRef.update({
        currentStatus: "active",
        suspendedAt: null,
        gracePeriodStartedAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Owner",
      module: "billing",
      action: "manual_payment_recorded",
      targetCollection: FirestorePaths.platformInvoices,
      targetId: invoiceId,
      newValue: {amount, method, referenceNumber: referenceNumber ?? null},
      success: true,
    });

    return {success: true};
  }
);
