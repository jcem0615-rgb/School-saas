import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {applyAssessment} from "../../shared/payments/balanceMath";
import {InstallmentData, validateInstallments} from "../../shared/payments/billingSchedule";
import {DiscountData, validateDiscounts} from "../../shared/payments/discounts";

interface FeeItemData {
  label: string;
  amount: number;
  category: string;
}

interface AssessStudentFeesData {
  schoolId: string;
  studentId: string;
  schoolYear: string;
  items: FeeItemData[];
  /**
   * When the money is expected. Absent or empty means the whole amount
   * falls due now, which is what an ad-hoc charge means and what every
   * assessment written before this field existed meant.
   */
  installments?: InstallmentData[];
  /**
   * What is being taken off the published fees, and why. The approver is
   * not in here -- it comes from the caller's own token.
   */
  discounts?: DiscountData[];
  /** The structure these came from, or absent for an ad-hoc charge. */
  sourceStructureId?: string;
  sourceStructureName?: string;
  remarks?: string;
}

// The same list that may collect a payment or set a balance. Charging a
// family money is a finance action; Faculty, Staff and Guidance have no
// business doing it.
const ALLOWED_ROLES = ["director", "admin", "registrar"];

const VALID_CATEGORIES = ["tuition", "miscellaneous", "other"];

/**
 * Charges a set of fees to a student, itemised.
 *
 * `balance` is deliberately not client-writable -- firestore.rules
 * rejects any student update touching it -- so this is a callable for the
 * same reason recordPayment and setStudentBalance are. What it adds is
 * the thing those two could not: a record of *what* was charged.
 *
 * Before this existed the only way to raise a balance was to type a total
 * into setStudentBalance, which left a family asking "why do we owe
 * 24,000?" with the figure and nothing behind it. An assessment answers
 * that question, and because the write and the balance change happen in
 * one transaction, the itemised list and the figure cannot drift apart.
 *
 * The items are copied in rather than referenced. A fee structure is a
 * template the school edits between years; an assessment is a thing that
 * happened to a family, and it should read the same in five years as it
 * did the day it was made.
 */
export const assessStudentFees = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<AssessStudentFeesData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {
      schoolId,
      studentId,
      schoolYear,
      items,
      installments,
      discounts,
      sourceStructureId,
      sourceStructureName,
      remarks,
    } = request.data;

    if (!schoolId || !studentId || !schoolYear) {
      throw new HttpsError("invalid-argument", "Missing assessment details.");
    }
    requireSameSchool(callerClaims, schoolId);

    if (!Array.isArray(items) || items.length === 0) {
      throw new HttpsError("invalid-argument", "An assessment needs at least one fee item.");
    }
    // A schedule with fifty lines is a spreadsheet, not a fee structure,
    // and the cap keeps one runaway payload from writing a document the
    // client then cannot render.
    if (items.length > 40) {
      throw new HttpsError("invalid-argument", "An assessment cannot have more than 40 items.");
    }

    let total = 0;
    const cleanItems = items.map((item, index) => {
      const label = (item?.label ?? "").trim();
      if (!label) {
        throw new HttpsError("invalid-argument", `Fee item ${index + 1} has no label.`);
      }
      const amount = Number(item?.amount);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new HttpsError(
          "invalid-argument",
          `"${label}" must cost more than zero. Remove the line instead.`
        );
      }
      if (amount > 1_000_000) {
        throw new HttpsError("invalid-argument", `"${label}" is out of range.`);
      }
      total += amount;
      const category = VALID_CATEGORIES.includes(item?.category) ? item.category : "other";
      return {label, amount: Math.round(amount * 100) / 100, category};
    });

    const grossTotal = Math.round(total * 100) / 100;
    if (grossTotal > 10_000_000) {
      throw new HttpsError("invalid-argument", "The assessment total is out of range.");
    }

    const {discounts: cleanDiscounts, discountTotal} = validateDiscounts(
      discounts,
      grossTotal,
      (request.auth!.token.name as string) ?? "Unknown"
    );

    // What the family is actually charged, and what moves the balance.
    total = Math.round((grossTotal - discountTotal) * 100) / 100;

    // Checked against the net, not the gross, and this is the join
    // between the two features: a family granted a 10% sibling discount
    // is on a plan for what they owe, not for what the schedule
    // publishes. Validating against the gross would refuse every
    // discounted family a payment plan.
    const cleanInstallments = validateInstallments(installments, total);

    const db = admin.firestore();
    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, studentId));
    const assessmentRef = db.collection(FirestorePaths.assessments(schoolId)).doc();

    // Charging the same schedule to the same student twice for the same
    // year is the mistake this feature makes easy: two clicks, and a
    // family silently owes double. Caught before the transaction because
    // it is a question about other documents, which a transaction read
    // would have to lock the whole collection to answer.
    if (sourceStructureId) {
      const duplicate = await db
        .collection(FirestorePaths.assessments(schoolId))
        .where("studentId", "==", studentId)
        .where("sourceStructureId", "==", sourceStructureId)
        .where("schoolYear", "==", schoolYear)
        .where("voidedAt", "==", null)
        .limit(1)
        .get();
      if (!duplicate.empty) {
        throw new HttpsError(
          "already-exists",
          "This student has already been assessed under that schedule for " +
            `${schoolYear}. Void the existing assessment first if it needs to change.`
        );
      }
    }

    const result = await db.runTransaction(async (tx) => {
      const studentSnap = await tx.get(studentRef);
      if (!studentSnap.exists) {
        throw new HttpsError("not-found", "Student record not found.");
      }
      const student = studentSnap.data()!;
      const previousBalance = (student.balance as number) ?? 0;
      const newBalance = applyAssessment(previousBalance, total);

      tx.set(assessmentRef, {
        id: assessmentRef.id,
        schoolId,
        studentId,
        studentName: `${student.firstName ?? ""} ${student.lastName ?? ""}`.trim(),
        schoolYear,
        sourceStructureId: sourceStructureId ?? null,
        sourceStructureName: sourceStructureName ?? null,
        items: cleanItems,
        installments: cleanInstallments,
        discounts: cleanDiscounts,
        // Both stored. `total` is what moved the balance and what every
        // reader means; `grossTotal` and `discountTotal` are what the
        // discounts report sums without re-deriving them from an array.
        grossTotal,
        discountTotal,
        total,
        assessedBy: request.auth!.uid,
        assessedByName: (request.auth!.token.name as string) ?? "Unknown",
        assessedAt: admin.firestore.FieldValue.serverTimestamp(),
        remarks: remarks?.trim() || null,
        // Written as null rather than omitted: the duplicate check above
        // queries on this field, and Firestore cannot match a document
        // that does not carry it.
        voidedAt: null,
        voidedBy: null,
        voidedByName: null,
        voidReason: null,
        isDeleted: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.update(studentRef, {
        balance: newBalance,
        updatedBy: request.auth!.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {previousBalance, newBalance};
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "",
      module: "payments",
      action: "assess_fees",
      targetCollection: FirestorePaths.assessments(schoolId),
      targetId: assessmentRef.id,
      previousValue: {balance: result.previousBalance},
      newValue: {balance: result.newBalance, total, items: cleanItems.length},
      success: true,
      remarks: sourceStructureName
        ? `Assessed ${sourceStructureName} for ${schoolYear}`
        : `Ad-hoc assessment for ${schoolYear}`,
    });

    return {
      assessmentId: assessmentRef.id,
      total,
      grossTotal,
      discountTotal,
      installments: cleanInstallments.length,
      previousBalance: result.previousBalance,
      balance: result.newBalance,
    };
  }
);
