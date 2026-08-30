import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  DEFAULT_MARK,
  blockRunsOn,
  classSessionId,
  subjectAttendanceId,
} from "../../shared/attendance/classSession";
import {schoolDateKey, schoolTimezone} from "../../shared/attendance/schoolClock";

interface OpenClassSessionData {
  schoolId: string;
  scheduleBlockId: string;
}

/**
 * Who may take a class register.
 *
 * The block's own teacher, always. Admin-tier roles as well, and only
 * for the reason substitutes exist: somebody has to be able to take the
 * register when the teacher is off sick, and "update the timetable
 * first" is not a thing anyone does at 7:28 in the morning. Who actually
 * pressed the button is recorded either way, so a register taken by a
 * cover teacher says so.
 *
 * Students, parents and staff are absent from this list on purpose, the
 * same one-way boundary the QR scanner draws: a compromised student
 * device must not be able to mark itself present.
 */
const COVER_ROLES = ["director", "principal", "admin"];
const ALLOWED_ROLES = ["faculty", ...COVER_ROLES];

/**
 * Time In: the teacher starts the class, and the roll appears.
 *
 * Opening a session writes a mark for every enrolled student in the
 * section, all of them present. Marking a register is marking
 * exceptions -- a teacher with forty students and three absences should
 * make three taps -- and a default of "unmarked" would mean a class that
 * ran to the bell and was never closed recorded nothing at all about the
 * thirty-seven children who were there.
 *
 * Idempotent, because the second press is not hypothetical: it is what
 * happens when the first one is slow and the teacher is holding a phone
 * in front of a class. The session id is derived from the date and the
 * timetabled block, so a second call finds the session already open and
 * returns it **without rebuilding the roll** -- rebuilding it would wipe
 * marks the teacher had already made.
 */
export const openClassSession = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<OpenClassSessionData>) => {
    const claims = requireCallerClaims(request);
    requireRole(claims, ALLOWED_ROLES);

    const {schoolId, scheduleBlockId} = request.data ?? ({} as OpenClassSessionData);
    if (!schoolId || !scheduleBlockId) {
      throw new HttpsError("invalid-argument", "Which class is this?");
    }
    requireSameSchool(claims, schoolId);

    const db = admin.firestore();
    const blockSnap = await db
      .doc(FirestorePaths.scheduleBlockDoc(schoolId, scheduleBlockId))
      .get();
    if (!blockSnap.exists || blockSnap.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "That class is not on the timetable.");
    }
    const block = blockSnap.data()!;

    const isOwnClass = block.teacherId === request.auth!.uid;
    if (!isOwnClass && !COVER_ROLES.includes(claims.role)) {
      // Named rather than a generic denial: a teacher who opened the
      // wrong row should learn that it is somebody else's class, not
      // assume the button is broken.
      throw new HttpsError(
        "permission-denied",
        `${block.subject ?? "That class"} is ${block.teacherName ?? "another teacher"}'s. ` +
          "Ask the office to cover it if you are taking it today."
      );
    }

    const timezone = await schoolTimezone(schoolId);
    const now = new Date();
    const dateKey = schoolDateKey(now, timezone);

    // A screen listing today's classes is not a guarantee: a stale list,
    // or a phone that slept through midnight, would otherwise file a
    // day's marks under the wrong date.
    if (!blockRunsOn(block.dayOfWeek as number, dateKey)) {
      throw new HttpsError(
        "failed-precondition",
        `${block.subject ?? "That class"} is not timetabled today.`
      );
    }

    const sessionId = classSessionId(dateKey, scheduleBlockId);
    const sessionRef = db.doc(FirestorePaths.classSessionDoc(schoolId, sessionId));

    const existing = await sessionRef.get();
    if (existing.exists) {
      // Already running, or already finished. Either way the roll it
      // holds is the teacher's work and is not to be replaced.
      const data = existing.data()!;
      return {
        sessionId,
        alreadyOpen: true,
        status: data.status as string,
        studentCount: (data.studentCount as number) ?? 0,
      };
    }

    // The section's roll, as it stands this morning. Enrolled only: a
    // transferred-out student is not somebody the teacher is looking at.
    const roster = await db
      .collection(FirestorePaths.students(schoolId))
      .where("section", "==", block.section)
      .where("status", "==", "enrolled")
      .where("isDeleted", "==", false)
      .get();

    const openedAt = admin.firestore.Timestamp.fromDate(now);
    const batch = db.batch();

    batch.set(sessionRef, {
      id: sessionId,
      schoolId,
      scheduleBlockId,
      subject: block.subject ?? "",
      section: block.section ?? "",
      room: block.room ?? null,
      schoolYear: block.schoolYear ?? "",
      term: block.term ?? null,
      // Who the timetable says teaches it, and who actually took it.
      // The same person almost always; when they differ, that difference
      // is the whole reason a cover register is worth reading.
      teacherId: block.teacherId ?? null,
      teacherName: block.teacherName ?? "",
      takenByUid: request.auth!.uid,
      takenByName: (request.auth!.token.name as string) ?? "",
      date: dateKey,
      openedAt,
      closedAt: null,
      status: "open",
      studentCount: roster.size,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: request.auth!.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
      deletedAt: null,
      deletedBy: null,
      isDeleted: false,
    });

    for (const student of roster.docs) {
      const data = student.data();
      batch.set(
        db.doc(
          FirestorePaths.subjectAttendanceDoc(
            schoolId,
            subjectAttendanceId(sessionId, student.id)
          )
        ),
        {
          id: subjectAttendanceId(sessionId, student.id),
          schoolId,
          sessionId,
          scheduleBlockId,
          studentId: student.id,
          studentName: `${data.firstName ?? ""} ${data.lastName ?? ""}`.trim(),
          // Denormalised so a student's own term-long subject history is
          // one query on this collection rather than a join back through
          // every session they sat in.
          subject: block.subject ?? "",
          section: block.section ?? "",
          date: dateKey,
          status: DEFAULT_MARK,
          timeIn: openedAt,
          timeOut: null,
          markedBy: request.auth!.uid,
          markedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdBy: request.auth!.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: request.auth!.uid,
          deletedAt: null,
          deletedBy: null,
          isDeleted: false,
        }
      );
    }

    await batch.commit();

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: claims.role,
      userName: (request.auth!.token.name as string) ?? "Teacher",
      module: "classSessions",
      action: isOwnClass ? "time_in" : "time_in_cover",
      targetCollection: FirestorePaths.classSessions(schoolId),
      targetId: sessionId,
      newValue: {
        subject: block.subject,
        section: block.section,
        studentCount: roster.size,
      },
      success: true,
    });

    return {
      sessionId,
      alreadyOpen: false,
      status: "open",
      studentCount: roster.size,
    };
  }
);
