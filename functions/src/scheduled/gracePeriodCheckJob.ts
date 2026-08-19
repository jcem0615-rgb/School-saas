import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {isPastSuspensionDeadline} from "../shared/billing/billingMath";
import {writeAuditLog} from "../shared/audit/writeAuditLog";
import {FirestorePaths} from "../shared/firestore-paths";

/**
 * Runs daily after dailyBillingJob. Walks every invoice past its due date:
 *  - if not yet flagged overdue, marks it overdue and starts the grace
 *    period clock on the school's subscription doc.
 *  - if the grace period has elapsed, auto-suspends the school.
 * A school manually paused by the Owner (see pauseSchool.ts) is left
 * alone here -- this job only ever transitions schools for *billing*
 * reasons, never touches a manual pause.
 */
export const gracePeriodCheckJob = onSchedule(
  {schedule: "30 0 * * *", timeZone: "Asia/Manila", region: "asia-southeast1"},
  async () => {
    const db = admin.firestore();
    const now = new Date();

    const overdueCandidates = await db
      .collection(FirestorePaths.platformInvoices)
      .where("status", "==", "pending")
      .where("dueDate", "<=", admin.firestore.Timestamp.fromDate(now))
      .get();

    for (const invoiceDoc of overdueCandidates.docs) {
      const invoice = invoiceDoc.data();
      const schoolId = invoice.schoolId as string;

      await invoiceDoc.ref.update({
        status: "overdue",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "system:gracePeriodCheckJob",
      });

      const schoolRef = db.doc(FirestorePaths.platformSchoolDoc(schoolId));
      const subscriptionRef = db.doc(FirestorePaths.platformSubscriptionDoc(schoolId));
      const [schoolSnap, subscriptionSnap] = await Promise.all([
        schoolRef.get(),
        subscriptionRef.get(),
      ]);
      const school = schoolSnap.data();
      const subscription = subscriptionSnap.data();
      if (!school || !subscription) continue;

      // Manually paused schools stay exactly as the Owner left them.
      if (subscription.currentStatus === "suspended" && !subscription.autoSuspendEnabled) {
        continue;
      }

      const gracePeriodDays = (school.gracePeriodDays as number) ?? 7;
      const gracePeriodStartedAt: Date =
        (subscription.gracePeriodStartedAt as admin.firestore.Timestamp | undefined)?.toDate() ??
        now;

      if (subscription.currentStatus !== "grace_period" && subscription.currentStatus !== "suspended") {
        await subscriptionRef.update({
          currentStatus: "grace_period",
          gracePeriodStartedAt: admin.firestore.Timestamp.fromDate(now),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: "system:gracePeriodCheckJob",
        });
        await writeAuditLog({
          schoolId,
          userId: "system",
          userRole: "system",
          userName: "Billing Engine",
          module: "subscription",
          action: "grace_period_started",
          targetCollection: FirestorePaths.platformSubscriptions,
          targetId: schoolId,
          success: true,
          remarks: `Invoice ${invoiceDoc.id} overdue.`,
        });
        continue;
      }

      if (
        subscription.currentStatus === "grace_period" &&
        isPastSuspensionDeadline(gracePeriodStartedAt, gracePeriodDays, now) &&
        subscription.autoSuspendEnabled !== false
      ) {
        await subscriptionRef.update({
          currentStatus: "suspended",
          suspendedAt: admin.firestore.FieldValue.serverTimestamp(),
          autoSuspendEnabled: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: "system:gracePeriodCheckJob",
        });
        await writeAuditLog({
          schoolId,
          userId: "system",
          userRole: "system",
          userName: "Billing Engine",
          module: "subscription",
          action: "auto_suspended",
          targetCollection: FirestorePaths.platformSubscriptions,
          targetId: schoolId,
          success: true,
          remarks: `Grace period of ${gracePeriodDays} days elapsed for invoice ${invoiceDoc.id}.`,
        });
      }
    }
  }
);
