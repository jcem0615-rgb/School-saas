import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {newMeetingRoom} from "../../shared/meeting/room";

interface SetModeData {
  schoolId: string;
  sessionId: string;
  /** "online" opens a room; "in_person" closes it. */
  mode: "online" | "in_person";
}

/** The same set that may open a register: the teacher, and cover. */
const COVER_ROLES = ["admin"];
const ALLOWED_ROLES = ["faculty", ...COVER_ROLES];

/** Firestore's per-batch ceiling. A roll is capped below this on open. */
const BATCH_LIMIT = 500;

/**
 * Takes today's lesson online, or brings it back into the room.
 *
 * The timetable does not decide this. A class is in person until the
 * person teaching it says otherwise, because the reasons are same-day
 * ones -- a typhoon, a suspension of classes, a teacher isolating -- and
 * a school that has to edit its timetable at 6am to hold a lesson will
 * not hold the lesson.
 *
 * ## Why the room is stamped onto every mark
 *
 * `classSessions` is staff-only in firestore.rules, deliberately: the
 * session document is the whole register and a student has no business
 * reading how the rest of the class came out. But the student is exactly
 * who needs the room.
 *
 * So the room goes where the student already has a document of their
 * own -- their line in the register, `subjectAttendance/{sessionId}_{studentId}`,
 * which they and their linked parent can already read and nobody else's
 * child can. No rule had to be widened to let a class be joined, which
 * is the part of this that would have been easy to get wrong.
 *
 * Clearing works the same way and matters as much: bringing the class
 * back in person removes the room from every mark, so a link screenshotted
 * this morning is not a door into this afternoon.
 */
export const setClassSessionMode = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetModeData>) => {
    const claims = requireCallerClaims(request);
    requireRole(claims, ALLOWED_ROLES);

    const {schoolId, sessionId, mode} = request.data ?? ({} as SetModeData);
    if (!schoolId || !sessionId) {
      throw new HttpsError("invalid-argument", "Which class is this?");
    }
    if (mode !== "online" && mode !== "in_person") {
      throw new HttpsError("invalid-argument", "A class is either online or in person.");
    }
    requireSameSchool(claims, schoolId);

    const db = admin.firestore();
    const sessionRef = db.doc(FirestorePaths.classSessionDoc(schoolId, sessionId));
    const snap = await sessionRef.get();
    if (!snap.exists || snap.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "That class has not been started yet.");
    }
    const session = snap.data()!;

    const isOwnClass = session.takenByUid === request.auth!.uid ||
      session.teacherId === request.auth!.uid;
    if (!isOwnClass && !COVER_ROLES.includes(claims.role)) {
      throw new HttpsError(
        "permission-denied",
        `${session.subject || "That class"} is ${session.teacherName || "another teacher"}'s.`
      );
    }

    // A closed register is a record of a lesson that finished. Opening a
    // room onto one would put a live class behind a document that says
    // the class is over, and nothing would ever close it again.
    if (session.status === "closed") {
      throw new HttpsError(
        "failed-precondition",
        "That class has already finished. Start it again to take it online."
      );
    }

    const goingOnline = mode === "online";
    // A fresh room every time, never a reused one: a room kept across
    // lessons is a door last term's leaver still has a key to.
    const room = goingOnline ? newMeetingRoom() : null;
    const now = admin.firestore.FieldValue.serverTimestamp();

    await sessionRef.update({
      deliveryMode: mode,
      meetingRoom: room,
      meetingOpenedAt: goingOnline ? now : null,
      updatedAt: now,
      updatedBy: request.auth!.uid,
    });

    // Every student's own line, so each of them can reach the room
    // without being able to read anybody else's.
    const marks = await db
      .collection(FirestorePaths.subjectAttendance(schoolId))
      .where("sessionId", "==", sessionId)
      .get();

    for (let i = 0; i < marks.docs.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const mark of marks.docs.slice(i, i + BATCH_LIMIT)) {
        batch.update(mark.ref, {meetingRoom: room, updatedAt: now});
      }
      await batch.commit();
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: claims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "classSessions",
      action: goingOnline ? "class_taken_online" : "class_returned_in_person",
      targetCollection: FirestorePaths.classSessions(schoolId),
      targetId: sessionId,
      // The room name is the secret that gets into the class, so it is
      // not copied into a log the whole office reads.
      newValue: {deliveryMode: mode, studentsNotified: marks.size},
      success: true,
      remarks: goingOnline ?
        `${session.subject || "A class"} moved online for ${marks.size} student` +
          `${marks.size === 1 ? "" : "s"}.` :
        `${session.subject || "A class"} brought back in person; the room was closed.`,
    });

    return {sessionId, deliveryMode: mode, meetingRoom: room, studentsReached: marks.size};
  }
);
