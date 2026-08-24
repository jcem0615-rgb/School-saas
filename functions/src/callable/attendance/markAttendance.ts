import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {computeAttendanceStatus, parseCutoffTime} from "../../shared/attendance/attendanceStatus";

interface MarkAttendanceData {
  qrToken: string;
  location?: string;
}

// Who each role may scan.
//
// Students and parents never appear as a key: they view attendance but can
// never mark it, a one-way boundary so a compromised student device could
// not forge its own "present" record.
//
// Beyond that, scanning is scoped to whose attendance a role is actually
// responsible for, and nothing wider:
//
//   faculty -> students   (a teacher takes class attendance)
//   admin   -> employees  (an admin runs staff timekeeping)
//
// Director, Principal and Registrar are deliberately NOT scanners. They
// were, briefly, on the reasoning that oversight roles should be able to
// cover any gate -- but "can cover a gate" and "can mark any person
// present from their own phone" are different powers, and only the second
// is what a scanner actually grants. Attendance is the record a payroll
// and a truancy report are built from; the narrower the set of accounts
// that can write it, the more it is worth.
const EMPLOYEE_ROLES = ["director", "principal", "admin", "registrar", "faculty", "staff", "guidance"];

const SCAN_MATRIX: Record<string, string[]> = {
  faculty: ["student"],
  admin: EMPLOYEE_ROLES,
};

const SCANNER_ALLOWED_ROLES = Object.keys(SCAN_MATRIX);

/**
 * Whether [scannerRole] is permitted to scan someone whose role is
 * [subjectRole]. Exported for the unit test, which is the only place the
 * whole matrix is asserted in one go.
 */
export function canScan(scannerRole: string, subjectRole: string): boolean {
  return (SCAN_MATRIX[scannerRole] ?? []).includes(subjectRole);
}

/** Resolves "now" to the school's local hour/minute using Intl, avoiding a moment.js-style dependency. */
function resolveSchoolLocalTime(now: Date, timezone: string): {hour: number; minute: number} {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour: "numeric",
    minute: "numeric",
    hourCycle: "h23",
  });
  const parts = formatter.formatToParts(now);
  const hour = Number(parts.find((p) => p.type === "hour")?.value ?? "0");
  const minute = Number(parts.find((p) => p.type === "minute")?.value ?? "0");
  return {hour, minute};
}

export const markAttendance = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<MarkAttendanceData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, SCANNER_ALLOWED_ROLES);

    const {qrToken, location} = request.data;
    if (!qrToken) {
      throw new HttpsError("invalid-argument", "qrToken is required.");
    }
    const schoolId = callerClaims.schoolId!;
    const db = admin.firestore();

    // QR tokens are opaque and tenant-scoped by construction (see
    // provisionUser.ts) -- looked up within the scanner's own school only,
    // never a global index. A token from another school simply won't match.
    const matchSnap = await db
      .collection(FirestorePaths.users(schoolId))
      .where("qrCode", "==", qrToken)
      .where("isDeleted", "==", false)
      .limit(1)
      .get();

    if (matchSnap.empty) {
      throw new HttpsError("not-found", "QR code not recognized for this school.");
    }
    const personDoc = matchSnap.docs[0];
    const person = personDoc.data();
    if (person.status !== "active") {
      throw new HttpsError("failed-precondition", `This account is ${person.status} and cannot be scanned.`);
    }

    const now = new Date();

    // Attendance, Payments, Grades, and Documents must all agree on what
    // identifies "a student" so that a Parent's `linkedStudentIds` (which
    // stores students/{studentId} academic-record IDs -- the ID that
    // exists whether or not a portal account does) means the same thing
    // everywhere. The scanned QR resolves to a `users/{uid}` account, so
    // for student scans we resolve the linked academic record and use
    // *that* ID as personId. Falls back to the account ID if no linked
    // academic record exists yet (e.g. Student Registration hasn't
    // created one) so scanning still works during interim rollout.
    let resolvedPersonId = personDoc.id;
    if (!canScan(callerClaims.role, person.role as string)) {
      // Names the subject's role rather than a generic denial, so a
      // teacher who scans a colleague's ID learns why instead of
      // assuming the scanner is broken.
      throw new HttpsError(
        "permission-denied",
        `Your role cannot record attendance for a ${person.role}.`
      );
    }

    if (person.role === "student") {
      const studentRecordSnap = await db
        .collection(FirestorePaths.students(schoolId))
        .where("userId", "==", personDoc.id)
        .where("isDeleted", "==", false)
        .limit(1)
        .get();
      if (!studentRecordSnap.empty) {
        resolvedPersonId = studentRecordSnap.docs[0].id;
      }
    }

    // Timezone lives on the platform-level school record (Admin SDK reads
    // bypass rules, so this is safe even though clients can't touch it).
    const schoolRecord = await db.doc(FirestorePaths.platformSchoolDoc(schoolId)).get();
    const timezone = (schoolRecord.data()?.timezone as string) ?? "Asia/Manila";
    const cutoffSetting = (await db.doc(FirestorePaths.school(schoolId)).get()).data()?.attendanceCutoffTime as
      | string
      | undefined;

    const {hour, minute} = resolveSchoolLocalTime(now, timezone);
    const cutoff = parseCutoffTime(cutoffSetting);
    const status = computeAttendanceStatus(hour, minute, cutoff.hour, cutoff.minute);

    const dateKey = new Intl.DateTimeFormat("en-CA", {timeZone: timezone}).format(now); // YYYY-MM-DD
    const recordId = `${dateKey}_${resolvedPersonId}`;
    const recordRef = db.doc(FirestorePaths.attendanceDoc(schoolId, recordId));

    const result = await db.runTransaction(async (tx) => {
      const existing = await tx.get(recordRef);

      if (!existing.exists) {
        tx.set(recordRef, {
          id: recordId,
          schoolId,
          personId: resolvedPersonId,
          personRole: person.role,
          subjectType: person.role === "student" ? "student" : "employee",
          method: "qr",
          date: dateKey,
          timestampIn: admin.firestore.Timestamp.fromDate(now),
          timestampOut: null,
          status,
          recordedBy: request.auth!.uid,
          location: location ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: request.auth!.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.auth!.uid,
          deletedAt: null,
          deletedBy: null,
          isDeleted: false,
        });
        return {action: "time_in", status};
      }

      const existingData = existing.data()!;
      if (!existingData.timestampOut) {
        tx.update(recordRef, {
          timestampOut: admin.firestore.Timestamp.fromDate(now),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.auth!.uid,
        });
        return {action: "time_out", status: existingData.status};
      }

      return {action: "already_completed", status: existingData.status};
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Scanner",
      module: "attendance",
      action: `qr_scan_${result.action}`,
      targetCollection: FirestorePaths.attendance(schoolId),
      targetId: recordId,
      newValue: {personId: resolvedPersonId, status: result.status},
      success: true,
    });

    return {
      personId: resolvedPersonId,
      personName: `${person.firstName ?? ""} ${person.lastName ?? ""}`.trim(),
      personRole: person.role,
      action: result.action, // 'time_in' | 'time_out' | 'already_completed'
      status: result.status, // 'present' | 'late'
      timestamp: now.toISOString(),
    };
  }
);
