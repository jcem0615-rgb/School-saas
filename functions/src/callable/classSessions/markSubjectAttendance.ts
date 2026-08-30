import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  canEditRoll,
  countRoll,
  subjectAttendanceId,
} from "../../shared/attendance/classSession";
import {schoolDateKey, schoolTimezone} from "../../shared/attendance/schoolClock";

interface MarkSubjectAttendanceData {
  schoolId: string;
  sessionId: string;
  studentId: string;
  status: string;
}

const MARKS = ["present", "late", "absent", "excused"];
const COVER_ROLES = ["director", "principal", "admin"];
const ALLOWED_ROLES = ["faculty", ...COVER_ROLES];

/**
 * One student, one class, one mark.
 *
 * Called when the teacher taps a name. Everybody starts present when the
 * session opens, so every call here is a correction: three taps for
 * three absences rather than forty taps for a full class.
 *
 * Only on the day the class was taken. A teacher who marked the wrong
 * name should fix it there and then, and closing the session does not
 * end that window -- Time Out means "the class is over", not "this is
 * now history". But a register that stays editable for a term is not a
 * record of what happened; it is a record of what somebody last thought.
 * After today it is the registrar's to amend, with the paperwork that
 * implies.
 */
export const markSubjectAttendance = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<MarkSubjectAttendanceData>) => {
    const claims = requireCallerClaims(request);
    requireRole(claims, ALLOWED_ROLES);

    const {schoolId, sessionId, studentId, status} =
      request.data ?? ({} as MarkSubjectAttendanceData);
    if (!schoolId || !sessionId || !studentId) {
      throw new HttpsError("invalid-argument", "Which student, in which class?");
    }
    requireSameSchool(claims, schoolId);
    if (!MARKS.includes(status)) {
      throw new HttpsError("invalid-argument", `"${status}" is not an attendance mark.`);
    }

    const db = admin.firestore();
    const sessionRef = db.doc(FirestorePaths.classSessionDoc(schoolId, sessionId));
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      throw new HttpsError("not-found", "That class was never started.");
    }
    const session = sessionSnap.data()!;

    if (session.takenByUid !== request.auth!.uid && !COVER_ROLES.includes(claims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only the teacher who took this class, or the office, can change its register."
      );
    }

    const timezone = await schoolTimezone(schoolId);
    const todayKey = schoolDateKey(new Date(), timezone);
    if (!canEditRoll(session.date as string, todayKey)) {
      throw new HttpsError(
        "failed-precondition",
        "This register is from an earlier day. Ask the registrar to amend it."
      );
    }

    const markRef = db.doc(
      FirestorePaths.subjectAttendanceDoc(schoolId, subjectAttendanceId(sessionId, studentId))
    );
    const markSnap = await markRef.get();
    if (!markSnap.exists) {
      // The roll is built when the session opens, from the section's
      // enrolled students. A name that is not on it is a student who
      // was not in this section this morning, and inventing a row for
      // them here would put a mark in a class they are not enrolled in.
      throw new HttpsError("not-found", "That student is not on this class's roll.");
    }
    const previous = markSnap.data()!;
    if (previous.status === status) {
      return {sessionId, studentId, status, changed: false};
    }

    const now = admin.firestore.Timestamp.now();
    const arriving = status === "present" || status === "late";

    await markRef.update({
      status,
      // Marked late halfway through the lesson: that is when they
      // arrived, and the session's start time is not.
      timeIn: arriving ? (previous.timeIn ?? now) : null,
      // A student turned absent after the class was closed keeps no
      // duration, for the same reason they get no time out.
      timeOut: arriving ? (previous.timeOut ?? null) : null,
      markedBy: request.auth!.uid,
      markedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    // Keep the session's counts honest when the register is corrected
    // after it was closed. An unclosed session has no counts yet --
    // closeClassSession computes them -- so there is nothing to fix.
    if (session.status === "closed") {
      const marks = await db
        .collection(FirestorePaths.subjectAttendance(schoolId))
        .where("sessionId", "==", sessionId)
        .get();
      await sessionRef.update({
        counts: countRoll(marks.docs.map((d) => (d.data().status as string) ?? "")),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: claims.role,
      userName: (request.auth!.token.name as string) ?? "Teacher",
      module: "classSessions",
      action: "mark",
      targetCollection: FirestorePaths.subjectAttendance(schoolId),
      targetId: markRef.id,
      previousValue: {status: previous.status},
      newValue: {
        status,
        studentId,
        subject: session.subject,
        section: session.section,
      },
      success: true,
    });

    return {sessionId, studentId, status, changed: true};
  }
);
