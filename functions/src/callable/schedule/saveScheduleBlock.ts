import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  findClashes,
  describeClash,
  TimetableBlock,
  MIN_CLASS_MINUTES,
  MAX_CLASS_MINUTES,
} from "../../shared/schedule/conflicts";

interface SaveScheduleBlockData {
  schoolId: string;
  /** Absent for a new class. */
  blockId?: string;
  subject: string;
  section: string;
  teacherId: string;
  teacherName: string;
  room?: string | null;
  dayOfWeek: number;
  startMinute: number;
  endMinute: number;
  schoolYear: string;
  term?: string | null;
}

// The timetable is an institutional decision, like the fee schedule. A
// teacher may not move their own class out of a clash with somebody
// else's.
const ALLOWED_ROLES = ["director", "principal", "admin"];

/**
 * Adds or moves one class on the timetable.
 *
 * A callable rather than a client write, for the reason clash detection
 * exists at all: a timetable whose only guarantee lives in the UI has no
 * guarantee. `firestore.rules` refuses every client write to
 * `scheduleBlocks`, so this is the only thing that can book a room.
 *
 * The clash query runs before the write and not inside a transaction.
 * Firestore transactions cannot query, and the alternative -- reading
 * the whole collection into the transaction to lock it -- would
 * serialise every timetable edit in the school against every other. Two
 * admins saving colliding classes in the same second can therefore both
 * succeed. That is a real race and it is the right trade: timetabling is
 * a once-a-term activity done by one or two people, the damage is a
 * visible double-booking rather than a silent one, and both blocks
 * remain editable afterwards. The alternative costs every school a
 * slower editor to protect against a collision most will never have.
 */
export const saveScheduleBlock = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SaveScheduleBlockData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {
      schoolId,
      blockId,
      subject,
      section,
      teacherId,
      teacherName,
      room,
      dayOfWeek,
      startMinute,
      endMinute,
      schoolYear,
      term,
    } = request.data;

    if (!schoolId || !schoolYear) {
      throw new HttpsError("invalid-argument", "Missing timetable details.");
    }
    requireSameSchool(callerClaims, schoolId);

    const cleanSubject = (subject ?? "").trim();
    const cleanSection = (section ?? "").trim();
    const cleanTeacherId = (teacherId ?? "").trim();
    if (!cleanSubject) throw new HttpsError("invalid-argument", "Name the subject.");
    if (!cleanSection) throw new HttpsError("invalid-argument", "Name the section.");
    if (!cleanTeacherId) throw new HttpsError("invalid-argument", "Choose a teacher.");

    if (!Number.isInteger(dayOfWeek) || dayOfWeek < 1 || dayOfWeek > 7) {
      throw new HttpsError("invalid-argument", "Choose a day of the week.");
    }
    if (
      !Number.isInteger(startMinute) ||
      !Number.isInteger(endMinute) ||
      startMinute < 0 ||
      endMinute > 24 * 60
    ) {
      throw new HttpsError("invalid-argument", "Those times are not on the clock.");
    }
    const duration = endMinute - startMinute;
    if (duration < MIN_CLASS_MINUTES) {
      throw new HttpsError("invalid-argument", "The class has to end after it starts.");
    }
    if (duration > MAX_CLASS_MINUTES) {
      throw new HttpsError(
        "invalid-argument",
        "That class runs longer than any school day. Check AM against PM."
      );
    }

    const db = admin.firestore();
    const collection = db.collection(FirestorePaths.scheduleBlocks(schoolId));

    const candidate: TimetableBlock = {
      id: blockId,
      subject: cleanSubject,
      section: cleanSection,
      teacherId: cleanTeacherId,
      teacherName: (teacherName ?? "").trim() || "Unknown",
      room: (room ?? "").trim() || null,
      dayOfWeek,
      startMinute,
      endMinute,
      schoolYear: schoolYear.trim(),
    };

    // Only the same day of the same year can clash, so that is all that
    // is read -- a school's whole timetable is a few hundred documents
    // and one day of it is a few dozen.
    const sameDay = await collection
      .where("schoolYear", "==", candidate.schoolYear)
      .where("dayOfWeek", "==", dayOfWeek)
      .where("isDeleted", "==", false)
      .get();

    const existing: TimetableBlock[] = sameDay.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        subject: (data.subject as string) ?? "",
        section: (data.section as string) ?? "",
        teacherId: (data.teacherId as string) ?? "",
        teacherName: (data.teacherName as string) ?? "",
        room: (data.room as string | null) ?? null,
        dayOfWeek: (data.dayOfWeek as number) ?? 0,
        startMinute: (data.startMinute as number) ?? 0,
        endMinute: (data.endMinute as number) ?? 0,
        schoolYear: (data.schoolYear as string) ?? "",
      };
    });

    const clashes = findClashes(candidate, existing);
    if (clashes.length > 0) {
      throw new HttpsError(
        "failed-precondition",
        clashes.map(describeClash).join(" ")
      );
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const payload = {
      schoolId,
      subject: candidate.subject,
      section: candidate.section,
      teacherId: candidate.teacherId,
      teacherName: candidate.teacherName,
      room: candidate.room,
      dayOfWeek,
      startMinute,
      endMinute,
      schoolYear: candidate.schoolYear,
      term: (term ?? "").trim() || null,
      isDeleted: false,
      updatedAt: now,
      updatedBy: request.auth!.uid,
      updatedByName: (request.auth!.token.name as string) ?? "Unknown",
    };

    const ref = blockId ? collection.doc(blockId) : collection.doc();
    if (blockId) {
      const snapshot = await ref.get();
      if (!snapshot.exists) throw new HttpsError("not-found", "That class is no longer on the timetable.");
      await ref.update(payload);
    } else {
      await ref.set({...payload, id: ref.id, createdAt: now, createdBy: request.auth!.uid});
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "",
      module: "schedule",
      action: blockId ? "update_schedule_block" : "create_schedule_block",
      targetCollection: FirestorePaths.scheduleBlocks(schoolId),
      targetId: ref.id,
      newValue: {
        subject: candidate.subject,
        section: candidate.section,
        dayOfWeek,
        startMinute,
        endMinute,
      },
      success: true,
      remarks: `${candidate.subject} for ${candidate.section}`,
    });

    return {blockId: ref.id};
  }
);
