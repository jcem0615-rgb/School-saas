import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {FirestorePaths} from "../../shared/firestore-paths";
import {isMeetingRoom} from "../../shared/meeting/room";
import {
  buildMeetingClaims,
  meetingTokenConfig,
  signMeetingToken,
} from "../../shared/meeting/token";

interface IssueTokenData {
  schoolId: string;
  sessionId: string;
}

/** The roles that run a lesson, and so arrive as moderator. */
const TEACHING_ROLES = ["faculty", "admin"];

/**
 * The pass that gets one person into one lesson, without a sign-in.
 *
 * They are already signed in -- to LogicClass, which knows who they are,
 * which class this is and whether they belong in it. This turns that
 * into something Jitsi will accept, so the video call never asks a
 * question the app has already answered.
 *
 * ## It re-asks the access question, it does not take the room on trust
 *
 * The caller says which *session*, never which room. The room is read
 * out of the record on the server, from the document that proves this
 * person is entitled to it:
 *
 *  * **staff** -- from the session itself, which they may only have if
 *    it is their class or they are cover.
 *  * **a student** -- from their own line in the register,
 *    `subjectAttendance/{sessionId}_{studentId}`. If there is no line,
 *    there is no token: a child who is not on the register for this
 *    lesson is not in this lesson.
 *
 * A caller who passes somebody else's session id gets nothing, because
 * nothing they own points at it. That is the same rule the rest of this
 * module runs on -- the student reaches the room through their own mark
 * and no other way -- carried over to the token rather than restated.
 *
 * ## An unconfigured school is not an error
 *
 * No signing key set means `{token: null}`, and the app joins the room
 * without one. That is exactly what it did before this existed: right on
 * a deployment that does not ask for a token, and Jitsi's own sign-in on
 * one that does. Turning the sign-in off is a deployment being
 * configured, not a code change -- see shared/meeting/token.ts.
 */
export const issueMeetingToken = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<IssueTokenData>) => {
    const claims = requireCallerClaims(request);
    const {schoolId, sessionId} = request.data ?? ({} as IssueTokenData);
    if (!schoolId || !sessionId) {
      throw new HttpsError("invalid-argument", "Which class is this?");
    }
    requireSameSchool(claims, schoolId);

    const db = admin.firestore();
    const uid = request.auth!.uid;
    const teaching = TEACHING_ROLES.includes(claims.role);

    let room: unknown = null;
    let moderator = false;

    if (teaching) {
      const snap = await db.doc(FirestorePaths.classSessionDoc(schoolId, sessionId)).get();
      if (!snap.exists || snap.data()?.isDeleted === true) {
        throw new HttpsError("not-found", "That class has not been started yet.");
      }
      const session = snap.data()!;
      const isOwnClass = session.takenByUid === uid || session.teacherId === uid;
      if (!isOwnClass && claims.role !== "admin") {
        throw new HttpsError(
          "permission-denied",
          `${session.subject || "That class"} is ${session.teacherName || "another teacher"}'s.`
        );
      }
      room = session.meetingRoom;
      // The person who runs the lesson: they can mute a disruptive
      // child and end the call for everybody, and nobody else can.
      moderator = true;
    } else {
      // Which child is this account? A student's user document does not
      // say -- the link lives on the student record, as `userId` -- so
      // it is resolved by query. firestore.rules cannot do this, which
      // is why the student's way into the room is a callable and not a
      // read.
      const mine = await db
        .collection(FirestorePaths.students(schoolId))
        .where("userId", "==", uid)
        .limit(1)
        .get();
      if (mine.empty) {
        throw new HttpsError(
          "permission-denied",
          "No student record is linked to this account."
        );
      }
      const markId = `${sessionId}_${mine.docs[0].id}`;
      const mark = await db.doc(FirestorePaths.subjectAttendanceDoc(schoolId, markId)).get();
      if (!mark.exists) {
        throw new HttpsError("permission-denied", "You are not in that class.");
      }
      room = mark.data()!.meetingRoom;
    }

    // Null once the lesson comes back in person or the register closes,
    // and that is the door shutting rather than a fault. Checked against
    // the pattern too: a value that reached the document by some other
    // route is not a room this app generated, and signing a token for it
    // would be signing a pass to somewhere unknown.
    if (!isMeetingRoom(room)) {
      throw new HttpsError("failed-precondition", "That class is not online.");
    }

    const config = meetingTokenConfig();
    if (!config) return {token: null, room};

    const token = signMeetingToken(
      buildMeetingClaims(
        {
          name: (request.auth!.token.name as string) || "LogicClass",
          email: (request.auth!.token.email as string) || undefined,
          moderator,
          room,
          now: Math.floor(Date.now() / 1000),
        },
        config
      ),
      config
    );

    // Deliberately not audit-logged. Every join would write a row naming
    // a room, the log is read school-wide, and the room name is the
    // whole of what keeps a stranger out of a class of children. That a
    // lesson went online is already recorded, by setClassSessionMode.
    return {token, room};
  }
);
