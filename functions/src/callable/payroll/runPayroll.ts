import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  CONTRIBUTION_LABELS,
  canIssuePayslips,
  schemeFromDoc,
  unconfiguredKinds,
} from "../../shared/payroll/contributions";
import {
  Payslip,
  compensationFromDoc,
  computePayslip,
  monthlyBasisFor,
} from "../../shared/payroll/payslip";
import {
  AttendanceScan,
  LeaveWindow,
  MAX_TIMESHEET_DAYS,
  TimesheetError,
  buildTimesheet,
  daysBetween,
  isDateKey,
} from "../../shared/payroll/timesheet";

interface RunPayrollData {
  schoolId: string;
  /** Inclusive 'YYYY-MM-DD' bounds. */
  periodFrom: string;
  periodTo: string;
  /**
   * False on the first cut-off of a semi-monthly month, so the month's
   * contributions are not taken twice.
   */
  deductContributions?: boolean;
  /**
   * False previews the run and writes nothing; true issues it.
   *
   * One flag rather than two callables, deliberately. The preview the
   * office approves and the payslips it then issues come out of the same
   * code path, so the figures on the screen cannot disagree with the
   * figures in the record.
   */
  commit?: boolean;
  /** A subset of staff, for re-running one person. All of them when absent. */
  employeeUids?: string[];
}

const PAYROLL_ROLES = ["director", "admin"];

/** How many employees are read at once. A school has tens, not thousands. */
const READ_CONCURRENCY = 10;

/**
 * A payroll run, computed on the server.
 *
 * Until this existed, what a school's staff were paid was worked out on
 * a clerk's device and written straight to Firestore, with the rules
 * checking only that the clerk held the right role. Anybody who could
 * open a console could have issued themselves a payslip for any figure
 * they liked, and the school's own record would have agreed with them.
 *
 * Everything the figures rest on is read here rather than accepted from
 * the caller: the pay rates, the contribution tables, the scans and the
 * approved leave. The client sends a period and a cut-off flag, which is
 * all it is in a position to know.
 */
export const runPayroll = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RunPayrollData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, periodFrom, periodTo, employeeUids} = request.data ?? {};
    const deductContributions = request.data?.deductContributions !== false;
    const commit = request.data?.commit === true;

    if (!schoolId) {
      throw new HttpsError("invalid-argument", "A payroll run needs a school.");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, PAYROLL_ROLES);

    if (!isDateKey(periodFrom) || !isDateKey(periodTo)) {
      throw new HttpsError("invalid-argument", "A payroll period needs two real dates.");
    }
    const span = daysBetween(periodFrom, periodTo);
    if (span === 0) {
      throw new HttpsError(
        "invalid-argument",
        "A payroll period cannot end before it starts."
      );
    }
    if (span > MAX_TIMESHEET_DAYS) {
      throw new HttpsError(
        "invalid-argument",
        `A payroll period cannot run longer than ${MAX_TIMESHEET_DAYS} days.`
      );
    }
    if (employeeUids !== undefined && !Array.isArray(employeeUids)) {
      throw new HttpsError("invalid-argument", "employeeUids must be a list of uids.");
    }

    const db = admin.firestore();

    const [compensationSnap, schemeSnap] = await Promise.all([
      db.collection(FirestorePaths.compensation(schoolId)).get(),
      db.doc(FirestorePaths.payrollSchemeDoc(schoolId)).get(),
    ]);

    const wanted = employeeUids && employeeUids.length > 0 ? new Set(employeeUids) : null;
    const staff = compensationSnap.docs
      .filter((doc) => !wanted || wanted.has(doc.id))
      .map((doc) => compensationFromDoc(doc.id, doc.data()))
      // A rate of zero is somebody half-entered on the compensation
      // screen, not somebody who works for nothing. Issuing them a
      // payslip for nought is worse than leaving them out of the run,
      // where the screen already names them as having no rate on file.
      .filter((person) => person.rate > 0);

    const scheme = schemeFromDoc(schemeSnap.data());
    const missing = unconfiguredKinds(scheme);
    const canIssue = canIssuePayslips(scheme);
    const blockers: string[] = [];
    if (missing.length > 0) {
      blockers.push(
        "These have no table yet: " +
          missing.map((kind) => CONTRIBUTION_LABELS[kind]).join(", ") +
          ". A payslip that silently deducts nothing for an agency is one " +
          "the school under-remits on all year."
      );
    } else if (!scheme.confirmedBySchool) {
      blockers.push(
        "The contribution tables have not been confirmed. Somebody has to " +
          "check them against the current circulars on the Payroll Setup " +
          "screen before payslips can be issued."
      );
    }

    const payslips: Payslip[] = [];
    for (let i = 0; i < staff.length; i += READ_CONCURRENCY) {
      const batch = staff.slice(i, i + READ_CONCURRENCY);
      const computed = await Promise.all(
        batch.map(async (person) => {
          const [records, leaves] = await Promise.all([
            readScans(db, schoolId, person.employeeUid, periodFrom, periodTo),
            readLeave(db, schoolId, person.employeeUid),
          ]);
          try {
            const timesheet = buildTimesheet({
              employeeUid: person.employeeUid,
              employeeName: person.employeeName,
              fromDate: periodFrom,
              toDate: periodTo,
              records,
              leaves,
            });
            return computePayslip({
              compensation: person,
              timesheet,
              scheme,
              monthlyBasisForContributions: monthlyBasisFor(person),
              deductContributions,
            });
          } catch (error) {
            if (error instanceof TimesheetError) {
              throw new HttpsError("invalid-argument", error.message);
            }
            throw error;
          }
        })
      );
      payslips.push(...computed);
    }
    payslips.sort((a, b) => a.employeeName.localeCompare(b.employeeName));

    if (!commit) {
      return {
        committed: false,
        issued: 0,
        canIssue,
        blockers,
        payslips,
      };
    }

    if (payslips.length === 0) {
      throw new HttpsError("failed-precondition", "Nobody to pay.");
    }
    if (!canIssue) {
      // The refusal that makes the confirmation mean something. These
      // are somebody's deductions, and this software asserts nothing
      // about what they should be until the school has said.
      throw new HttpsError("failed-precondition", blockers[0]);
    }

    const refs = payslips.map((payslip) =>
      db.doc(
        FirestorePaths.payslipDoc(schoolId, periodFrom, periodTo, payslip.employeeUid)
      )
    );

    // Read first so the refusal names who was already paid, rather than
    // coming back as a bare ALREADY_EXISTS from the write below. The
    // write still uses `create`, because between this read and that
    // write is exactly where two clerks issuing the same run at once
    // would otherwise both succeed.
    const existing = (await db.getAll(...refs))
      .map((snap, index) => (snap.exists ? payslips[index].employeeName : null))
      .filter((name): name is string => name !== null);
    if (existing.length > 0) {
      throw new HttpsError(
        "already-exists",
        `This period has already been issued for ${existing.join(", ")}. ` +
          "A payslip cannot be edited afterwards, so a correction is a fresh " +
          "one for a different period rather than a second run of this one."
      );
    }

    const issuedBy = request.auth!.uid;
    const issuedByName = (request.auth!.token.name as string) ?? "Unknown";
    const now = admin.firestore.FieldValue.serverTimestamp();

    const batch = db.batch();
    payslips.forEach((payslip, index) => {
      // `create`, not `set`. Firestore refuses the whole batch if any of
      // these documents already exists, which is what makes running the
      // same period twice fail loudly instead of paying somebody twice.
      batch.create(refs[index], {
        ...payslip,
        id: refs[index].id,
        schoolId,
        deductedContributions: deductContributions,
        issuedBy,
        issuedByName,
        issuedAt: now,
        createdAt: now,
        createdBy: issuedBy,
        updatedAt: now,
        updatedBy: issuedBy,
        deletedAt: null,
        deletedBy: null,
        isDeleted: false,
      });
    });

    try {
      await batch.commit();
    } catch (error) {
      // ALREADY_EXISTS. The race the read above cannot close.
      if ((error as {code?: number}).code === 6) {
        throw new HttpsError(
          "already-exists",
          "Somebody issued this period while this run was being prepared. " +
            "Nothing was written twice."
        );
      }
      throw error;
    }

    await writeAuditLog({
      schoolId,
      userId: issuedBy,
      userRole: callerClaims.role,
      userName: issuedByName,
      module: "payroll",
      action: "payslips_issued",
      targetCollection: FirestorePaths.payslips(schoolId),
      targetId: `${periodFrom}_${periodTo}`,
      newValue: {
        periodFrom,
        periodTo,
        count: payslips.length,
        deductContributions,
        netPay: payslips.reduce((sum, p) => sum + p.netPay, 0),
        employerContributions: payslips.reduce(
          (sum, p) => sum + p.employerContributions,
          0
        ),
      },
      success: true,
    });

    return {
      committed: true,
      issued: payslips.length,
      canIssue,
      blockers,
      payslips,
    };
  }
);

/**
 * The employee's scans for the period.
 *
 * Per employee rather than one range query over the whole school: the
 * attendance collection holds every student's gate scan too, and a month
 * of those is thousands of documents to read and throw away. This shape
 * matches the (personId, date) index the timesheet screen already uses.
 */
async function readScans(
  db: admin.firestore.Firestore,
  schoolId: string,
  employeeUid: string,
  periodFrom: string,
  periodTo: string
): Promise<AttendanceScan[]> {
  const snap = await db
    .collection(FirestorePaths.attendance(schoolId))
    .where("personId", "==", employeeUid)
    .where("date", ">=", periodFrom)
    .where("date", "<=", periodTo)
    .get();

  return snap.docs.map((doc) => {
    const data = doc.data();
    return {
      personId: (data.personId as string) ?? "",
      date: (data.date as string) ?? "",
      timestampIn: toDate(data.timestampIn) ?? new Date(0),
      timestampOut: toDate(data.timestampOut),
      status: (data.status as string) ?? "present",
    };
  });
}

/**
 * Every leave request this employee has filed.
 *
 * Unfiltered on status and date because both are cheap in memory and
 * neither is cheap in an index: a school of a hundred staff files a few
 * hundred of these a year, and one equality on employeeUid is served by
 * the automatic single-field index. `buildTimesheet` keeps only the
 * approved ones covering a day in the period.
 */
async function readLeave(
  db: admin.firestore.Firestore,
  schoolId: string,
  employeeUid: string
): Promise<LeaveWindow[]> {
  const snap = await db
    .collection(FirestorePaths.leaveRequests(schoolId))
    .where("employeeUid", "==", employeeUid)
    .limit(500)
    .get();

  return snap.docs
    .filter((doc) => doc.data().isDeleted !== true)
    .map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        employeeUid: (data.employeeUid as string) ?? "",
        status: (data.status as string) ?? "pending",
        type: (data.type as string) ?? "unpaid",
        fromDate: (data.fromDate as string) ?? "",
        toDate: (data.toDate as string) ?? "",
      };
    });
}

function toDate(raw: unknown): Date | null {
  if (raw instanceof admin.firestore.Timestamp) return raw.toDate();
  if (raw instanceof Date) return raw;
  return null;
}
