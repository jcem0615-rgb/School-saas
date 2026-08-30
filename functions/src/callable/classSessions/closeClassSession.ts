import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {countRoll, sessionMinutes} from "../../shared/attendance/classSession";

interface CloseClassSessionData {
  schoolId: string;
  sessionId: string;
}

const COVER_ROLES = ["director", "principal", "admin"];
const ALLOWED_ROLES = ["faculty", ...COVER_ROLES];

/**
 * Time Out: the class is over.
 *
 * Stamps the end time on the session and on every student who was
 * actually in it, which is what turns "present" into "present, 7:32 to
 * 8:20". A student marked absent gets no time out, because they had no
 * time in.
 *
 * The counts are written onto the session at the same moment. They could
 * be recomputed on every read instead, but a register is read far more
 * often than it is taken -- by the teacher tomorrow, the adviser at the
 * end of the week, the parent whenever they wonder -- and forty document
 * reads to render one line is the difference between a screen that opens
 * and one that spins.
 *
 * Idempotent. A session already closed is returned as it stands rather
 * than closed a second time with a later timestamp: the first Time Out
 * is when the class ended.
 */
export const closeClassSession = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<CloseClassSessionData>) => {
    const claims = requireCallerClaims(request);
    requireRole(claims, ALLOWED_ROLES);

    const {schoolId, sessionId} = request.data ?? ({} as CloseClassSessionData);
    if (!schoolId || !sessionId) {
      throw new HttpsError("invalid-argument", "Which class is this?");
    }
    requireSameSchool(claims, schoolId);

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
        "Only the teacher who started this class, or the office, can end it."
      );
    }

    if (session.status === "closed") {
      return {
        sessionId,
        alreadyClosed: true,
        minutes: session.minutes ?? null,
      };
    }

    const marks = await db
      .collection(FirestorePaths.subjectAttendance(schoolId))
      .where("sessionId", "==", sessionId)
      .get();

    const now = new Date();
    const closedAt = admin.firestore.Timestamp.fromDate(now);
    const openedAt = (session.openedAt as admin.firestore.Timestamp | undefined)?.toDate() ?? now;
    const minutes = sessionMinutes(openedAt, now);

    const counts = countRoll(marks.docs.map((d) => (d.data().status as string) ?? ""));

    const batch = db.batch();
    batch.update(sessionRef, {
      status: "closed",
      closedAt,
      minutes,
      counts,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    for (const mark of marks.docs) {
      const status = mark.data().status as string;
      // Only the students who were there. An absent student has no time
      // out because they had no time in, and writing one would put a
      // duration against a child who was not in the room.
      if (status !== "present" && status !== "late") continue;
      batch.update(mark.ref, {
        timeOut: closedAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    }

    await batch.commit();

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: claims.role,
      userName: (request.auth!.token.name as string) ?? "Teacher",
      module: "classSessions",
      action: "time_out",
      targetCollection: FirestorePaths.classSessions(schoolId),
      targetId: sessionId,
      newValue: {subject: session.subject, section: session.section, minutes, ...counts},
      success: true,
    });

    return {sessionId, alreadyClosed: false, minutes, counts};
  }
);
