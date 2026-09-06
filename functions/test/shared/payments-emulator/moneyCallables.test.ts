/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/payments-emulator"
 *
 * The four callables that move a student's balance, against a real
 * Firestore. The arithmetic is covered pure in
 * test/shared/payments/balanceMath.test.ts; what is tested here is
 * everything the pure functions cannot see.
 *
 * The reason this is emulator-backed rather than mocked is the same
 * reason `balance` is server-owned in the first place. Every one of these
 * re-reads the student inside a transaction and recomputes the balance
 * from what it finds -- the client never supplies the new figure. A
 * stubbed transaction cannot fail the way a real one does under
 * contention, so the guarantee that matters most here can only be tested
 * against a real database:
 *
 *   * two cashiers taking a payment at once must leave a balance that is
 *     down by both amounts, not by whichever wrote last;
 *   * one refund clicked twice must return the money once.
 *
 * Both are quiet failures. Nothing errors, the screen looks right, and
 * the discrepancy is found weeks later by a family who was charged for a
 * payment they made.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_money";
const OTHER_SCHOOL = "school_money_other";
const STUDENT = "stu_miguel";

/* eslint-disable @typescript-eslint/no-explicit-any */
let callRecordPayment: any;
let callRecordRefund: any;
let callAssessFees: any;
let callVoidAssessment: any;
/* eslint-enable @typescript-eslint/no-explicit-any */

function db() {
  return admin.firestore();
}

function caller(role: string, uid = `${role}_1`, schoolId: string | undefined = SCHOOL) {
  return {
    uid,
    token: {role, schoolId, status: "active", mustChangePassword: false, name: `${role} one`},
  };
}

async function balanceOf(studentId = STUDENT, schoolId = SCHOOL): Promise<number> {
  const snap = await db().doc(FirestorePaths.studentDoc(schoolId, studentId)).get();
  return snap.data()?.balance as number;
}

async function paymentRows(schoolId = SCHOOL) {
  const snap = await db().collection(FirestorePaths.payments(schoolId)).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()}));
}

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.students(schoolId),
    FirestorePaths.payments(schoolId),
    FirestorePaths.assessments(schoolId),
    FirestorePaths.auditLog(schoolId),
    FirestorePaths.receiptBooklets(schoolId),
    `schools/${schoolId}/counters`,
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed(balance = 0) {
  await wipe(SCHOOL);
  await wipe(OTHER_SCHOOL);
  await db().doc(FirestorePaths.studentDoc(SCHOOL, STUDENT)).set({
    id: STUDENT,
    schoolId: SCHOOL,
    studentNumber: "2026-00001",
    firstName: "Miguel",
    lastName: "Torres",
    educationLevel: "high_school",
    gradeLevel: "Grade 10",
    section: "Grade 10 - Rizal",
    status: "enrolled",
    balance,
    isDeleted: false,
  });
}

const cash = (amount: number) => ({
  schoolId: SCHOOL,
  studentId: STUDENT,
  amount,
  method: "cash",
  purpose: "tuition",
});

describe("the callables that move money", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const [pay, refund, assess, voidIt] = await Promise.all([
      import("../../../src/callable/payments/recordPayment"),
      import("../../../src/callable/payments/recordRefund"),
      import("../../../src/callable/payments/assessStudentFees"),
      import("../../../src/callable/payments/voidAssessment"),
    ]);
    callRecordPayment = fft.wrap(pay.recordPayment);
    callRecordRefund = fft.wrap(refund.recordRefund);
    callAssessFees = fft.wrap(assess.assessStudentFees);
    callVoidAssessment = fft.wrap(voidIt.voidAssessment);
  });

  afterAll(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    fft.cleanup();
  });

  describe("recording a payment", () => {
    beforeEach(() => seed(10000));

    it("takes the amount off what the family owes", async () => {
      await callRecordPayment({data: cash(2500), auth: caller("registrar")} as never);

      expect(await balanceOf()).toBe(7500);
      const rows = await paymentRows();
      expect(rows).toHaveLength(1);
      expect(rows[0].amount).toBe(2500);
      expect(rows[0].receiptNumber).toBeTruthy();
    });

    it("computes the new balance from the record, not from anything sent", async () => {
      // The client cannot supply a balance, and this is what makes that
      // matter: a stale figure on a cashier's screen -- another window,
      // another cashier, a payment taken a minute ago -- must not become
      // the stored one.
      await callRecordPayment({data: cash(1000), auth: caller("registrar")} as never);
      // Somebody else moves the balance behind our back.
      await db().doc(FirestorePaths.studentDoc(SCHOOL, STUDENT)).update({balance: 4000});
      await callRecordPayment({data: cash(1000), auth: caller("registrar")} as never);

      // 4000 - 1000, not 9000 - 1000. The second call read what was
      // actually there.
      expect(await balanceOf()).toBe(3000);
    });

    it("lets a balance go negative, because an overpayment is a credit", async () => {
      await callRecordPayment({data: cash(12000), auth: caller("registrar")} as never);
      expect(await balanceOf()).toBe(-2000);
    });

    it("keeps centavos, and does not drift over several payments", async () => {
      for (const amount of [33.33, 33.33, 33.34]) {
        await callRecordPayment({data: cash(amount), auth: caller("registrar")} as never);
      }
      expect(await balanceOf()).toBe(9900);
    });

    it("refuses nothing, or less than nothing", async () => {
      for (const amount of [0, -100]) {
        await expect(
          callRecordPayment({data: cash(amount), auth: caller("registrar")} as never)
        ).rejects.toThrow();
      }
      expect(await balanceOf()).toBe(10000);
    });

    it("insists on a reference for money that arrived electronically", async () => {
      // Cash has a receipt. A GCash payment with no reference cannot be
      // matched against the school's own statement afterwards, which is
      // the only way to tell a real one from a mistaken entry.
      await expect(
        callRecordPayment({
          data: {...cash(500), method: "gcash"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/reference number/i);

      await callRecordPayment({
        data: {...cash(500), method: "gcash", referenceNumber: "GC-11223344"},
        auth: caller("registrar"),
      } as never);
      expect(await balanceOf()).toBe(9500);
    });

    it("refuses a student who is not on file", async () => {
      await expect(
        callRecordPayment({
          data: {...cash(500), studentId: "stu_nobody"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/not found/i);
      expect(await paymentRows()).toHaveLength(0);
    });

    it("refuses the roles that have no business handling money", async () => {
      for (const role of ["faculty", "guidance", "staff", "student", "parent", "principal"]) {
        await expect(
          callRecordPayment({data: cash(500), auth: caller(role)} as never)
        ).rejects.toThrow();
      }
      expect(await balanceOf()).toBe(10000);
    });

    it("two cashiers at once take both amounts off, not one", async () => {
      // The case the transaction exists for. Whichever wrote last winning
      // would leave a family credited for one payment and charged for the
      // other, and nothing on either screen would look wrong.
      await Promise.all(
        Array.from({length: 5}, () =>
          callRecordPayment({data: cash(1000), auth: caller("registrar")} as never)
        )
      );

      expect(await paymentRows()).toHaveLength(5);
      expect(await balanceOf()).toBe(5000);
    });

    it("gives five simultaneous payments five different receipt numbers", async () => {
      await Promise.all(
        Array.from({length: 5}, () =>
          callRecordPayment({data: cash(100), auth: caller("registrar")} as never)
        )
      );
      const receipts = (await paymentRows()).map((p) => p.receiptNumber);
      expect(new Set(receipts).size).toBe(5);
    });
  });

  describe("refunding a payment", () => {
    beforeEach(() => seed(10000));

    async function takeAPayment(amount = 2500) {
      const result = await callRecordPayment({
        data: cash(amount),
        auth: caller("registrar"),
      } as never);
      return (await paymentRows())[0].id as string ?? result.paymentId;
    }

    it("puts back exactly what was taken", async () => {
      const paymentId = await takeAPayment(2500);
      expect(await balanceOf()).toBe(7500);

      await callRecordRefund({
        data: {schoolId: SCHOOL, paymentId, reason: "Paid twice at the counter"},
        auth: caller("director"),
      } as never);

      expect(await balanceOf()).toBe(10000);
    });

    it("refuses a registrar, who may take money but not give it back", async () => {
      // A cashier who can both take and reverse a payment unilaterally is
      // a classic embezzlement vector. Requiring a more senior role is a
      // real control, not a formality.
      const paymentId = await takeAPayment();
      await expect(
        callRecordRefund({
          data: {schoolId: SCHOOL, paymentId, reason: "mine now"},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow();
      expect(await balanceOf()).toBe(7500);
    });

    it("insists on a reason", async () => {
      const paymentId = await takeAPayment();
      await expect(
        callRecordRefund({
          data: {schoolId: SCHOOL, paymentId, reason: "  "},
          auth: caller("director"),
        } as never)
      ).rejects.toThrow(/reason/i);
    });

    it("refunds once when the button is clicked twice", async () => {
      // The quiet one. A double refund hands the family money the school
      // never took, and the balance is the only place it shows.
      const paymentId = await takeAPayment(2500);

      const results = await Promise.allSettled(
        Array.from({length: 4}, () =>
          callRecordRefund({
            data: {schoolId: SCHOOL, paymentId, reason: "Paid twice"},
            auth: caller("director"),
          } as never)
        )
      );

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      expect(await balanceOf()).toBe(10000);
    });

    it("refuses to refund the same payment again later", async () => {
      const paymentId = await takeAPayment(2500);
      await callRecordRefund({
        data: {schoolId: SCHOOL, paymentId, reason: "Paid twice"},
        auth: caller("director"),
      } as never);

      await expect(
        callRecordRefund({
          data: {schoolId: SCHOOL, paymentId, reason: "again"},
          auth: caller("director"),
        } as never)
      ).rejects.toThrow(/already been refunded/i);
      expect(await balanceOf()).toBe(10000);
    });

    it("refuses a payment that is not on file", async () => {
      await expect(
        callRecordRefund({
          data: {schoolId: SCHOOL, paymentId: "pay_nobody", reason: "x"},
          auth: caller("director"),
        } as never)
      ).rejects.toThrow(/not found/i);
    });
  });

  describe("assessing fees", () => {
    beforeEach(() => seed(0));

    const items = [
      {label: "Tuition", amount: 15000, category: "tuition"},
      {label: "Miscellaneous", amount: 3500, category: "misc"},
    ];
    const assessment = {
      schoolId: SCHOOL,
      studentId: STUDENT,
      schoolYear: "2026-2027",
      items,
    };

    it("raises what the family owes by the total of the items", async () => {
      await callAssessFees({data: assessment, auth: caller("registrar")} as never);
      expect(await balanceOf()).toBe(18500);
    });

    it("adds to an existing balance rather than replacing it", async () => {
      // The difference between a charge and setStudentBalance, and the
      // reason the latter is a separate, audited action.
      await seed(2000);
      await callAssessFees({data: assessment, auth: caller("registrar")} as never);
      expect(await balanceOf()).toBe(20500);
    });

    it("refuses an assessment with nothing in it", async () => {
      await expect(
        callAssessFees({data: {...assessment, items: []}, auth: caller("registrar")} as never)
      ).rejects.toThrow(/at least one fee item/i);
      expect(await balanceOf()).toBe(0);
    });

    it("refuses an item with no label, which is a charge nobody can query", async () => {
      await expect(
        callAssessFees({
          data: {...assessment, items: [{label: "  ", amount: 500, category: "misc"}]},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/no label/i);
    });

    it("refuses an absurd amount rather than storing it", async () => {
      // A slipped decimal point or a pasted account number. Stored, it
      // becomes a balance a family is told they owe.
      await expect(
        callAssessFees({
          data: {
            ...assessment,
            items: [{label: "Tuition", amount: 999999999999, category: "tuition"}],
          },
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/out of range/i);
      expect(await balanceOf()).toBe(0);
    });

    it("refuses a caller from another school", async () => {
      await expect(
        callAssessFees({
          data: assessment,
          auth: caller("registrar", "registrar_elsewhere", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow();
      expect(await balanceOf()).toBe(0);
    });
  });

  describe("voiding an assessment", () => {
    beforeEach(() => seed(0));

    async function assess() {
      await callAssessFees({
        data: {
          schoolId: SCHOOL,
          studentId: STUDENT,
          schoolYear: "2026-2027",
          items: [{label: "Tuition", amount: 15000, category: "tuition"}],
        },
        auth: caller("registrar"),
      } as never);
      const snap = await db().collection(FirestorePaths.assessments(SCHOOL)).get();
      return snap.docs[0].id;
    }

    it("takes the charge back off the balance", async () => {
      const assessmentId = await assess();
      expect(await balanceOf()).toBe(15000);

      await callVoidAssessment({
        data: {schoolId: SCHOOL, assessmentId, reason: "Charged the wrong student"},
        auth: caller("registrar"),
      } as never);

      expect(await balanceOf()).toBe(0);
    });

    it("leaves the assessment visible rather than deleting it", async () => {
      // A wrong charge stays on the record, marked void. The history of a
      // family's account is never quietly rewritten.
      const assessmentId = await assess();
      await callVoidAssessment({
        data: {schoolId: SCHOOL, assessmentId, reason: "Wrong student"},
        auth: caller("registrar"),
      } as never);

      const snap = await db().doc(`${FirestorePaths.assessments(SCHOOL)}/${assessmentId}`).get();
      expect(snap.exists).toBe(true);
      // Marked by the presence of voidedAt rather than a boolean, which
      // is also what the callable itself checks to refuse a second void.
      expect(snap.data()?.voidedAt).toBeDefined();
      expect(snap.data()?.voidReason).toBe("Wrong student");
      expect(snap.data()?.voidedByName).toBeTruthy();
    });

    it("voids once when clicked twice", async () => {
      const assessmentId = await assess();
      const results = await Promise.allSettled(
        Array.from({length: 4}, () =>
          callVoidAssessment({
            data: {schoolId: SCHOOL, assessmentId, reason: "Wrong student"},
            auth: caller("registrar"),
          } as never)
        )
      );

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      expect(await balanceOf()).toBe(0);
    });

    it("insists on a reason", async () => {
      const assessmentId = await assess();
      await expect(
        callVoidAssessment({
          data: {schoolId: SCHOOL, assessmentId, reason: ""},
          auth: caller("registrar"),
        } as never)
      ).rejects.toThrow(/reason/i);
      expect(await balanceOf()).toBe(15000);
    });
  });

  describe("the ledger and the balance agree", () => {
    it("after a mixed run of charges, payments, a refund and a void", async () => {
      // The property that actually matters to a school: whatever sequence
      // of actions happened, the balance is the sum of what was charged
      // minus what was paid. Asserted end to end rather than per action,
      // because these are the four things that touch it and any pair of
      // them getting out of step is invisible until a family asks.
      await seed(0);

      const assessmentIds: string[] = [];
      for (const amount of [15000, 3500]) {
        await callAssessFees({
          data: {
            schoolId: SCHOOL,
            studentId: STUDENT,
            schoolYear: "2026-2027",
            items: [{label: "Fee", amount, category: "misc"}],
          },
          auth: caller("registrar"),
        } as never);
      }
      const assessments = await db().collection(FirestorePaths.assessments(SCHOOL)).get();
      assessments.docs.forEach((d) => assessmentIds.push(d.id));
      expect(await balanceOf()).toBe(18500);

      await callRecordPayment({data: cash(5000), auth: caller("registrar")} as never);
      await callRecordPayment({data: cash(2500), auth: caller("registrar")} as never);
      expect(await balanceOf()).toBe(11000);

      const refundable = (await paymentRows()).find((p) => p.amount === 2500)!.id as string;
      await callRecordRefund({
        data: {schoolId: SCHOOL, paymentId: refundable, reason: "Paid twice"},
        auth: caller("director"),
      } as never);
      expect(await balanceOf()).toBe(13500);

      const voidable = assessments.docs.find((d) => d.data().total === 3500)!.id;
      await callVoidAssessment({
        data: {schoolId: SCHOOL, assessmentId: voidable, reason: "Charged in error"},
        auth: caller("registrar"),
      } as never);

      // 18500 charged, 3500 voided, 5000 paid and kept, 2500 paid and
      // refunded: 18500 - 3500 - 5000 = 10000.
      expect(await balanceOf()).toBe(10000);
    });
  });
});
