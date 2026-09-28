import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  forgetWrongPasscodes,
  recordWrongPasscode,
  refuseIfLockedOut,
} from "../../shared/meeting/attempts";
import {passcodeMatches} from "../../shared/meeting/passcode";
import {isMeetingRoom} from "../../shared/meeting/room";
import {LearnerScope, scopeFrom, scopeRefusal} from "../../shared/meeting/scope";
import {
  buildLiveKitClaims,
  liveKitConfig,
  signLiveKitToken,
} from "../../shared/meeting/livekit";

interface IssueTokenData {
  schoolId: string;
  sessionId: string;
  /** What the teacher read out. Not needed by the teacher themselves. */
  passcode?: string;
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
 * ## Four locks, and why none of them is enough alone
 *
 * An invitation link gets pasted into a group chat and screenshotted.
 * So the link is only an address, and everything that decides who comes
 * in is checked here:
 *
 *  1. **The school.** From the caller's own claims, before anything is
 *     read.
 *  2. **The register.** A line of their own in this lesson, or the
 *     lesson is theirs to teach.
 *  3. **The passcode.** Read out to the people who are actually in the
 *     lesson, and never in the link. The register says whether a child
 *     is in this class; it cannot say whether the child is the one
 *     holding the phone, and in a school it often is not -- accounts
 *     are shared between siblings and a tablet goes round a house.
 *     Wrong codes are counted, and eight of them close the door for ten
 *     minutes. See shared/meeting/attempts.ts.
 *  4. **The scope.** Section, grade level, department, education level,
 *     programme -- compared against the record as it stands now, not as
 *     it stood when the roll was taken. A register is a photograph; a
 *     child can be moved between sections by the afternoon and their
 *     mark still points at this morning's lesson. See
 *     shared/meeting/scope.ts.
 *
 * The teacher is asked for no code: they are the one who sets it, and a
 * teacher locked out of their own lesson by their own passcode is a
 * lesson that does not happen.
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
    const {schoolId, sessionId, passcode} = request.data ?? ({} as IssueTokenData);
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

      // The lesson's own record, read with the server's privileges. The
      // student cannot read this document -- classSessions is staff-only
      // -- which is exactly why the passcode is kept on it and the room
      // is copied onto the mark instead.
      const lesson = await db
        .doc(FirestorePaths.classSessionDoc(schoolId, sessionId))
        .get();
      if (!lesson.exists || lesson.data()?.isDeleted === true) {
        throw new HttpsError("not-found", "That class has not been started yet.");
      }
      const session = lesson.data()!;

      // Where they belong now, not where they belonged when the roll
      // was taken this morning.
      const refusal = scopeRefusal(
        scopeFrom(session.scope),
        mine.docs[0].data() as LearnerScope,
        {schoolId}
      );
      if (refusal) {
        throw new HttpsError("permission-denied", refusal);
      }

      const required = session.meetingPasscode;
      if (typeof required === "string" && required.length > 0) {
        await refuseIfLockedOut(schoolId, sessionId, uid, new Date());
        if (!passcodeMatches(passcode, required)) {
          await recordWrongPasscode(schoolId, sessionId, uid);
          throw new HttpsError(
            "permission-denied",
            "That is not the code for this class. Your teacher reads it " +
              "out at the start of the lesson."
          );
        }
        // Otherwise a child who mistyped it seven times this morning
        // starts the afternoon one keystroke from being locked out.
        await forgetWrongPasscodes(schoolId, sessionId, uid);
      }
    }

    // Null once the lesson comes back in person or the register closes,
    // and that is the door shutting rather than a fault. Checked against
    // the pattern too: a value that reached the document by some other
    // route is not a room this app generated, and signing a token for it
    // would be signing a pass to somewhere unknown.
    if (!isMeetingRoom(room)) {
      throw new HttpsError("failed-precondition", "That class is not online.");
    }

    // A media server first, where the school has one. It is the only
    // shape that carries a class of sixty -- everybody sends once and it
    // forwards -- and the app draws the video itself, so there is no
    // third-party document for anybody to refuse to embed.
    const live = liveKitConfig();
    if (live) {
      return {
        provider: "livekit",
        url: live.url,
        room,
        token: signLiveKitToken(
          buildLiveKitClaims(
            {
              name: (request.auth!.token.name as string) || "LogicClass",
              // Stable per person, so rejoining after a dropped
              // connection replaces them in the room rather than
              // leaving a ghost beside them.
              identity: uid,
              room,
              moderator,
              now: Math.floor(Date.now() / 1000),
            },
            live
          ),
          live
        ),
      };
    }

    // No media server configured. The screens say so plainly rather
    // than sending a class at something that will not work, which is
    // what the embedded fallback did until it was removed.
    return {provider: "none", token: null, room};
  }
);
