import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {computeDailyCharge} from "../shared/billing/billingMath";
import {FirestorePaths} from "../shared/firestore-paths";

/**
 * Runs once daily (00:05 Asia/Manila, after midnight so "today's" active
 * count is stable). For every non-archived school:
 *  1. Counts currently enrolled students (status == 'enrolled').
 *  2. Computes today's charge (activeStudents x billingRatePerStudent).
 *  3. Appends that charge to the current month's open invoice (creating
 *     one on the 1st of each cycle).
 *  4. Updates platform_subscriptions with the fresh snapshot.
 * Finally recomputes the single platform_revenue_summary/current doc so
 * the Owner Dashboard stays O(1) to read regardless of school count.
 */
export const dailyBillingJob = onSchedule(
  {schedule: "5 0 * * *", timeZone: "Asia/Manila", region: "asia-southeast1"},
  async () => {
    const db = admin.firestore();
    const schoolsSnap = await db.collection(FirestorePaths.platformSchools).get();

    let totalDailyRevenue = 0;
    let totalActiveStudents = 0;
    let activeSchoolCount = 0;

    const today = new Date();
    const todayKey = today.toISOString().slice(0, 10); // YYYY-MM-DD
    const monthKey = todayKey.slice(0, 7); // YYYY-MM

    for (const schoolDoc of schoolsSnap.docs) {
      const school = schoolDoc.data();
      if (school.status === "archived") continue;

      const schoolId = schoolDoc.id;
      const rate = (school.billingRatePerStudent as number) ?? 3.0;

      const studentsSnap = await db
        .collection(FirestorePaths.students(schoolId))
        .where("status", "==", "enrolled")
        .where("isDeleted", "==", false)
        .count()
        .get();
      const activeStudentCount = studentsSnap.data().count;

      const dailyCharge = computeDailyCharge(activeStudentCount, rate);

      const subscriptionRef = db.doc(FirestorePaths.platformSubscriptionDoc(schoolId));
      const subscriptionSnap = await subscriptionRef.get();
      const subscriptionData = subscriptionSnap.data();

      // Suspended schools still get counted for reporting but do not
      // accrue further charges -- billing a school you've cut off would
      // be indefensible to a paying customer.
      const isSuspended = subscriptionData?.currentStatus === "suspended";

      const invoiceId = `${schoolId}_${monthKey}`;
      const invoiceRef = db.doc(FirestorePaths.platformInvoiceDoc(invoiceId));

      if (!isSuspended) {
        await db.runTransaction(async (tx) => {
          const invoiceSnap = await tx.get(invoiceRef);
          const periodStart = new Date(`${monthKey}-01T00:00:00Z`);
          const periodEnd = new Date(periodStart);
          periodEnd.setMonth(periodEnd.getMonth() + 1);

          const newLine = {date: todayKey, activeStudents: activeStudentCount, charge: dailyCharge};

          if (!invoiceSnap.exists) {
            tx.set(invoiceRef, {
              id: invoiceId,
              schoolId,
              billingPeriodStart: admin.firestore.Timestamp.fromDate(periodStart),
              billingPeriodEnd: admin.firestore.Timestamp.fromDate(periodEnd),
              dailyBreakdown: [newLine],
              totalAmount: dailyCharge,
              status: "pending",
              dueDate: admin.firestore.Timestamp.fromDate(periodEnd),
              paidAt: null,
              paidAmount: null,
              paymentMethod: null,
              paymentReference: null,
              recordedBy: null,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              createdBy: "system:dailyBillingJob",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedBy: "system:dailyBillingJob",
              deletedAt: null,
              deletedBy: null,
              isDeleted: false,
            });
          } else {
            const existing = invoiceSnap.data()!;
            const breakdown = (existing.dailyBreakdown ?? []).filter(
              (line: {date: string}) => line.date !== todayKey // idempotent re-runs for the same day
            );
            breakdown.push(newLine);
            const totalAmount = breakdown.reduce(
              (sum: number, line: {charge: number}) => sum + line.charge,
              0
            );
            tx.update(invoiceRef, {
              dailyBreakdown: breakdown,
              totalAmount: Math.round(totalAmount * 100) / 100,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedBy: "system:dailyBillingJob",
            });
          }

          tx.set(
            subscriptionRef,
            {
              schoolId,
              activeStudentCountSnapshot: activeStudentCount,
              lastBilledDate: admin.firestore.Timestamp.fromDate(today),
              currentCycleAccrued: admin.firestore.FieldValue.increment(dailyCharge),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedBy: "system:dailyBillingJob",
            },
            {merge: true}
          );
        });

        totalDailyRevenue += dailyCharge;
      }

      totalActiveStudents += activeStudentCount;
      if (subscriptionData?.currentStatus === "active") activeSchoolCount++;
    }

    // Roll up month-to-date and year-to-date from paid + pending invoices
    // this cycle/year rather than re-summing every school's full history
    // on every run -- acceptable cost once per day, not per dashboard load.
    const monthStart = new Date(`${monthKey}-01T00:00:00Z`);
    const yearStart = new Date(`${todayKey.slice(0, 4)}-01-01T00:00:00Z`);

    const [monthInvoices, yearInvoices, overdueInvoices, suspendedSubs] = await Promise.all([
      db
        .collection(FirestorePaths.platformInvoices)
        .where("billingPeriodStart", ">=", admin.firestore.Timestamp.fromDate(monthStart))
        .get(),
      db
        .collection(FirestorePaths.platformInvoices)
        .where("billingPeriodStart", ">=", admin.firestore.Timestamp.fromDate(yearStart))
        .get(),
      db.collection(FirestorePaths.platformInvoices).where("status", "==", "overdue").count().get(),
      db
        .collection(FirestorePaths.platformSubscriptions)
        .where("currentStatus", "==", "suspended")
        .count()
        .get(),
    ]);

    const monthlyRevenue = monthInvoices.docs.reduce((s, d) => s + (d.data().totalAmount ?? 0), 0);
    const yearlyRevenue = yearInvoices.docs.reduce((s, d) => s + (d.data().totalAmount ?? 0), 0);

    await db.doc("platform_revenue_summary/current").set({
      dailyRevenue: totalDailyRevenue,
      monthlyRevenue,
      yearlyRevenue,
      activeSchoolCount,
      totalActiveStudents,
      overdueSchoolCount: overdueInvoices.data().count,
      suspendedSchoolCount: suspendedSubs.data().count,
      lastUpdated: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);
