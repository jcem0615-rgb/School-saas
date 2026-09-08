/**
 * Requires the Firestore emulator.
 * Run via: firebase emulators:exec --only firestore "jest test/shared/payroll-emulator"
 *
 * `runPayroll`, against a real Firestore.
 *
 * The arithmetic is covered pure in test/shared/payroll/. What is tested
 * here is everything the pure functions cannot see, and all of it is the
 * reason the computation moved to the server in the first place:
 *
 *   * that the figures come from the pay rates, contribution tables,
 *     scans and approved leave *on file*, and not from anything the
 *     caller sent;
 *   * that the preview and the issue produce the same numbers, because
 *     they are the same call;
 *   * that a period issued twice pays nobody twice, including when two
 *     clerks press Issue at the same moment;
 *   * that an unconfirmed contribution table refuses.
 *
 * The last two are quiet failures. Nothing errors, the screen looks
 * right, and a school finds out on payday.
 */
import functionsTest from "firebase-functions-test";
import * as admin from "firebase-admin";
import {FirestorePaths} from "../../../src/shared/firestore-paths";

const fft = functionsTest({projectId: "school-saas-test"});

const SCHOOL = "school_payroll";
const OTHER_SCHOOL = "school_payroll_other";
const TEACHER = "emp_maria";

// A fortnight: ten working days, Mon 1 June to Fri 12 June 2026.
const FROM = "2026-06-01";
const TO = "2026-06-12";
const WORKED = [1, 2, 3, 4, 5, 8, 9, 10, 11, 12];

/* eslint-disable @typescript-eslint/no-explicit-any */
let callRunPayroll: any;
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

const period = (over: Record<string, unknown> = {}) => ({
  schoolId: SCHOOL,
  periodFrom: FROM,
  periodTo: TO,
  ...over,
});

async function wipe(schoolId: string) {
  for (const path of [
    FirestorePaths.compensation(schoolId),
    FirestorePaths.payslips(schoolId),
    FirestorePaths.attendance(schoolId),
    FirestorePaths.leaveRequests(schoolId),
    FirestorePaths.auditLog(schoolId),
  ]) {
    const snap = await db().collection(path).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await db().doc(FirestorePaths.payrollSchemeDoc(schoolId)).delete();
}

const bracket = (over: Record<string, unknown>) => ({
  to: null,
  fixedAmount: 0,
  percentOfExcess: 0,
  employerFixedAmount: 0,
  employerPercentOfExcess: 0,
  ...over,
});

/** The same deliberately simple scheme the pure tests use. */
const TABLES = [
  {
    kind: "sss",
    sourceLabel: "SSS Circular (school-entered)",
    brackets: [bracket({from: 0, fixedAmount: 1350, employerFixedAmount: 2650})],
  },
  {
    kind: "philhealth",
    sourceLabel: null,
    brackets: [bracket({from: 0, percentOfExcess: 2.5, employerPercentOfExcess: 2.5})],
  },
  {
    kind: "pagibig",
    sourceLabel: null,
    brackets: [bracket({from: 0, fixedAmount: 200, employerFixedAmount: 200})],
  },
  {
    kind: "withholding_tax",
    sourceLabel: "RR (school-entered)",
    brackets: [
      bracket({from: 0, to: 20833}),
      bracket({from: 20833.01, percentOfExcess: 15}),
    ],
  },
];

async function setScheme(opts: {confirmed?: boolean; tables?: unknown[]} = {}) {
  await db().doc(FirestorePaths.payrollSchemeDoc(SCHOOL)).set({
    tables: opts.tables ?? TABLES,
    confirmedBySchool: opts.confirmed !== false,
    confirmedByName: "Office",
  });
}

async function setRate(
  employeeUid: string,
  over: Record<string, unknown> = {}
) {
  await db().doc(FirestorePaths.compensationDoc(SCHOOL, employeeUid)).set({
    employeeUid,
    employeeName: "Maria Santos",
    basis: "monthly",
    rate: 30000,
    allowance: 0,
    deductAbsences: true,
    schoolId: SCHOOL,
    ...over,
  });
}

async function addScan(
  day: number,
  opts: {personId?: string; inHour?: number; outHour?: number | null; status?: string} = {}
) {
  const date = `2026-06-${String(day).padStart(2, "0")}`;
  const personId = opts.personId ?? TEACHER;
  const outHour = opts.outHour === undefined ? 16 : opts.outHour;
  await db().doc(FirestorePaths.attendanceDoc(SCHOOL, `${date}_${personId}`)).set({
    personId,
    personRole: "faculty",
    subjectType: "employee",
    date,
    timestampIn: admin.firestore.Timestamp.fromDate(
      new Date(`${date}T${String(opts.inHour ?? 7).padStart(2, "0")}:00:00Z`)
    ),
    timestampOut: outHour === null
      ? null
      : admin.firestore.Timestamp.fromDate(new Date(`${date}T${String(outHour).padStart(2, "0")}:00:00Z`)),
    status: opts.status ?? "present",
    schoolId: SCHOOL,
  });
}

async function fullFortnight(personId = TEACHER) {
  for (const day of WORKED) await addScan(day, {personId});
}

async function payslipRows(schoolId = SCHOOL) {
  const snap = await db().collection(FirestorePaths.payslips(schoolId)).get();
  return snap.docs.map((d) => ({id: d.id, ...d.data()} as Record<string, unknown>));
}

describe("running payroll", () => {
  beforeAll(async () => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
    const module = await import("../../../src/callable/payroll/runPayroll");
    callRunPayroll = fft.wrap(module.runPayroll);
  });

  afterAll(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    fft.cleanup();
  });

  beforeEach(async () => {
    await wipe(SCHOOL);
    await wipe(OTHER_SCHOOL);
    await setScheme();
    await setRate(TEACHER);
    await fullFortnight();
  });

  describe("who may run it", () => {
    it("is the Admin", async () => {
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips).toHaveLength(1);
    });

    it("is not the Director, who reads a payslip without running the payroll", async () => {
      // Supervision, not operation. What somebody is paid is exactly the
      // kind of figure a Director must be able to see and must not be
      // able to set on their own.
      for (const role of ["director", "principal"]) {
        await expect(
          callRunPayroll({data: period(), auth: caller(role)} as never)
        ).rejects.toThrow(/role/i);
      }
    });

    it("is not the registrar, who handles every other peso", async () => {
      // The registrar takes tuition all day and has no business knowing
      // what the principal earns.
      await expect(
        callRunPayroll({data: period(), auth: caller("registrar")} as never)
      ).rejects.toThrow(/role/i);
    });

    it("is not the employee whose payslip it is", async () => {
      await expect(
        callRunPayroll({data: period(), auth: caller("faculty", TEACHER)} as never)
      ).rejects.toThrow(/role/i);
    });

    it("is nobody at all when signed out", async () => {
      await expect(callRunPayroll({data: period()} as never)).rejects.toThrow(/signed in/i);
    });

    it("is not an admin of another school", async () => {
      await expect(
        callRunPayroll({
          data: period(),
          auth: caller("admin", "admin_b", OTHER_SCHOOL),
        } as never)
      ).rejects.toThrow(/access/i);
    });
  });

  describe("where the figures come from", () => {
    it("the rate on file, and nothing the caller sent", async () => {
      // The whole reason this moved off the device. A client that could
      // name its own figure could issue itself any payslip it liked.
      const result = await callRunPayroll({
        data: period({
          rate: 900000,
          basicPay: 900000,
          netPay: 900000,
          payslips: [{employeeUid: TEACHER, netPay: 900000}],
          daysWorked: 30,
        }),
        auth: caller("admin"),
      } as never);

      expect(result.payslips).toHaveLength(1);
      expect(result.payslips[0].earnings[0].amount).toBe(30000);
      expect(result.payslips[0].daysWorked).toBe(10);
    });

    it("the scans on file, so a day nobody worked comes off the pay", async () => {
      await db()
        .doc(FirestorePaths.attendanceDoc(SCHOOL, `2026-06-01_${TEACHER}`))
        .delete();
      await db()
        .doc(FirestorePaths.attendanceDoc(SCHOOL, `2026-06-02_${TEACHER}`))
        .delete();

      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips[0].daysAbsent).toBe(2);
      // Ten working days in the period, so a day is 3,000.
      expect(result.payslips[0].basicPay).toBe(24000);
    });

    it("approved leave, which is not absence", async () => {
      await db().doc(FirestorePaths.attendanceDoc(SCHOOL, `2026-06-01_${TEACHER}`)).delete();
      await db().collection(FirestorePaths.leaveRequests(SCHOOL)).doc("lv_1").set({
        employeeUid: TEACHER,
        status: "approved",
        type: "sick",
        fromDate: "2026-06-01",
        toDate: "2026-06-01",
        isDeleted: false,
      });

      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips[0].daysAbsent).toBe(0);
      expect(result.payslips[0].basicPay).toBe(30000);
    });

    it("only leave that was actually approved", async () => {
      // A pending request is a plan. Counting it would let anybody take
      // a paid day by filing for it.
      await db().doc(FirestorePaths.attendanceDoc(SCHOOL, `2026-06-01_${TEACHER}`)).delete();
      await db().collection(FirestorePaths.leaveRequests(SCHOOL)).doc("lv_1").set({
        employeeUid: TEACHER,
        status: "pending",
        type: "sick",
        fromDate: "2026-06-01",
        toDate: "2026-06-01",
        isDeleted: false,
      });

      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips[0].daysAbsent).toBe(1);
    });

    it("nobody else's scans", async () => {
      await addScan(1, {personId: "emp_someone_else"});
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips[0].daysWorked).toBe(10);
    });

    it("only this school's", async () => {
      await db().doc(FirestorePaths.compensationDoc(OTHER_SCHOOL, "emp_other")).set({
        employeeName: "Somebody Else",
        basis: "monthly",
        rate: 99999,
      });
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips.map((p: {employeeUid: string}) => p.employeeUid)).toEqual([TEACHER]);
    });

    it("skips somebody half-entered on the compensation screen", async () => {
      // A rate of zero is not somebody who works for nothing. The run
      // screen names them as having no rate on file; issuing them a
      // payslip for nought would say the school had paid them.
      await setRate("emp_halfway", {rate: 0, employeeName: "Half Entered"});
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips).toHaveLength(1);
    });
  });

  describe("previewing", () => {
    it("writes nothing", async () => {
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.committed).toBe(false);
      expect(result.issued).toBe(0);
      expect(await payslipRows()).toHaveLength(0);
    });

    it("previews even when the tables are not confirmed, and says why not", async () => {
      // A half-configured school can still see what the figures would
      // be while it works through them. The refusal is at issuing.
      await setScheme({confirmed: false});
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.payslips).toHaveLength(1);
      expect(result.canIssue).toBe(false);
      expect(result.blockers[0]).toMatch(/not been confirmed/i);
    });

    it("names the agency a school has not filled in yet", async () => {
      await setScheme({tables: TABLES.slice(0, 2)});
      const result = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      expect(result.blockers[0]).toContain("Pag-IBIG");
      expect(result.blockers[0]).toContain("Withholding tax");
    });
  });

  describe("issuing", () => {
    it("writes exactly what the preview showed", async () => {
      // The point of one callable with a flag rather than two: the
      // figures the office approved and the figures in the record cannot
      // be two different computations.
      const preview = await callRunPayroll({data: period(), auth: caller("admin")} as never);
      const issued = await callRunPayroll({
        data: period({commit: true}),
        auth: caller("admin"),
      } as never);

      expect(issued.committed).toBe(true);
      expect(issued.issued).toBe(1);
      expect(issued.payslips).toEqual(preview.payslips);

      const rows = await payslipRows();
      expect(rows).toHaveLength(1);
      expect(rows[0].netPay).toBe(preview.payslips[0].netPay);
      expect(rows[0].id).toBe(`${FROM}_${TO}_${TEACHER}`);
      expect(rows[0].issuedBy).toBe("admin_1");
    });

    it("refuses when the contribution tables are not confirmed", async () => {
      // The refusal that makes the confirmation mean something. These
      // are somebody's deductions, and this asserts nothing about what
      // they should be until the school has said.
      await setScheme({confirmed: false});
      await expect(
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never)
      ).rejects.toThrow(/not been confirmed/i);
      expect(await payslipRows()).toHaveLength(0);
    });

    it("refuses when an agency has no table at all", async () => {
      await setScheme({tables: TABLES.slice(0, 3)});
      await expect(
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never)
      ).rejects.toThrow(/Withholding tax/);
      expect(await payslipRows()).toHaveLength(0);
    });

    it("refuses a period with nobody to pay", async () => {
      await db().doc(FirestorePaths.compensationDoc(SCHOOL, TEACHER)).delete();
      await expect(
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never)
      ).rejects.toThrow(/Nobody to pay/i);
    });

    it("pays nobody twice when the same period is run again", async () => {
      await callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never);
      await expect(
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never)
      ).rejects.toThrow(/already been issued/i);
      expect(await payslipRows()).toHaveLength(1);
    });

    it("names who has already been paid", async () => {
      await callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never);
      await expect(
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never)
      ).rejects.toThrow(/Maria Santos/);
    });

    it("pays nobody twice when two clerks press Issue at the same moment", async () => {
      // The read that names who was already paid cannot close this
      // window; `create` does. Both hands land in the same instant, one
      // batch commits, the other is refused -- and the school pays one
      // payroll rather than two.
      const results = await Promise.allSettled([
        callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never),
        callRunPayroll({data: period({commit: true}), auth: caller("director")} as never),
      ]);

      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
      expect(await payslipRows()).toHaveLength(1);
      // The same ceiling the payments suite's contention tests carry: two
      // batches racing take longer than Jest's five-second default when
      // several emulator suites share one Firestore, and a timeout there
      // would read as a failure of a guarantee that in fact held.
    }, 30_000);

    it("adds a second employee to a run without disturbing the first", async () => {
      await setRate("emp_ana", {employeeName: "Ana Cruz", rate: 24000});
      await fullFortnight("emp_ana");

      const result = await callRunPayroll({
        data: period({commit: true}),
        auth: caller("admin"),
      } as never);
      expect(result.issued).toBe(2);

      const rows = await payslipRows();
      expect(rows.map((r) => r.id).sort()).toEqual([
        `${FROM}_${TO}_emp_ana`,
        `${FROM}_${TO}_${TEACHER}`,
      ].sort());
    });

    it("records what was issued in the audit log", async () => {
      await callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never);
      const snap = await db().collection(FirestorePaths.auditLog(SCHOOL)).get();
      const entry = snap.docs
        .map((d) => d.data())
        .find((d) => d.action === "payslips_issued");
      expect(entry).toBeDefined();
      expect(entry!.userId).toBe("admin_1");
      expect((entry!.newValue as {count: number}).count).toBe(1);
    });

    it("does not take the month's contributions twice on a semi-monthly run", async () => {
      // Turned off for the first cut-off. Taking them on both halves
      // takes double from everybody, and nobody notices until somebody
      // checks their own payslip.
      const result = await callRunPayroll({
        data: period({deductContributions: false}),
        auth: caller("admin"),
      } as never);
      expect(result.payslips[0].deductions).toEqual([]);
      expect(result.payslips[0].netPay).toBe(30000);
    });
  });

  describe("the period asked for", () => {
    it("refuses one that runs backwards", async () => {
      await expect(
        callRunPayroll({
          data: period({periodFrom: TO, periodTo: FROM}),
          auth: caller("admin"),
        } as never)
      ).rejects.toThrow(/before it starts/i);
    });

    it("refuses a date that is not one", async () => {
      for (const bad of ["2026-6-1", "last month", "2026-02-31"]) {
        await expect(
          callRunPayroll({data: period({periodFrom: bad}), auth: caller("admin")} as never)
        ).rejects.toThrow(/real dates/i);
      }
    });

    it("refuses a year-long period, which is a mistyped one", async () => {
      await expect(
        callRunPayroll({
          data: period({periodFrom: "2026-01-01", periodTo: "2026-12-31"}),
          auth: caller("admin"),
        } as never)
      ).rejects.toThrow(/longer than/i);
    });

    it("leaves a period already issued alone when a different one is run", async () => {
      await callRunPayroll({data: period({commit: true}), auth: caller("admin")} as never);
      const july = await callRunPayroll({
        data: period({periodFrom: "2026-07-01", periodTo: "2026-07-15", commit: true}),
        auth: caller("admin"),
      } as never);

      expect(july.issued).toBe(1);
      expect(await payslipRows()).toHaveLength(2);
    });
  });
});
