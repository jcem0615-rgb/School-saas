import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  conversationId,
  isLinkedParent,
  teachesSection,
} from "../../shared/messaging/conversation";

interface StartConversationData {
  schoolId: string;
  studentId: string;
  /** The other person. A parent names the teacher; a teacher names the parent. */
  otherUid: string;
}

/**
 * Opens the thread between a parent and one of their child's teachers,
 * or returns the one that already exists.
 *
 * The relationship is checked here and nowhere else, because checking it
 * needs a query -- which of this teacher's assignments covers that
 * section -- and firestore.rules can only fetch a document by path. Once
 * this has written the conversation, membership *is* a field on a
 * document, which is a thing rules can police, so every message after
 * this one is an ordinary client write.
 *
 * Idempotent: the id is derived from the three people involved, so two
 * people opening a conversation with each other in the same moment land
 * in the same thread rather than in two, each holding half of it.
 */
export const startConversation = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<StartConversationData>) => {
    const claims = requireCallerClaims(request);
    const {schoolId, studentId, otherUid} =
      request.data ?? ({} as StartConversationData);

    if (!schoolId || !studentId || !otherUid) {
      throw new HttpsError("invalid-argument", "Who, about which student?");
    }
    requireSameSchool(claims, schoolId);

    const callerUid = request.auth!.uid;
    if (callerUid === otherUid) {
      throw new HttpsError("invalid-argument", "You cannot message yourself.");
    }

    // Which of the two is the teacher decides everything below, and it
    // comes from the caller's own token rather than from the request.
    let teacherUid: string;
    let parentUid: string;
    if (claims.role === "parent") {
      parentUid = callerUid;
      teacherUid = otherUid;
    } else if (claims.role === "faculty") {
      teacherUid = callerUid;
      parentUid = otherUid;
    } else {
      // Deliberately nobody else. A conversation between a parent and a
      // teacher is between the two of them; an admin who needs to say
      // something to a family has announcements, and one who needs to
      // read this has a lawful-request path, not a back door.
      throw new HttpsError(
        "permission-denied",
        "Only a teacher and a parent can open a conversation."
      );
    }

    const db = admin.firestore();
    const [studentSnap, parentSnap, teacherSnap, assignmentsSnap] = await Promise.all([
      db.doc(FirestorePaths.studentDoc(schoolId, studentId)).get(),
      db.doc(FirestorePaths.userDoc(schoolId, parentUid)).get(),
      db.doc(FirestorePaths.userDoc(schoolId, teacherUid)).get(),
      db
        .collection(FirestorePaths.teacherAssignments(schoolId))
        .where("teacherId", "==", teacherUid)
        .get(),
    ]);

    const student = studentSnap.data();
    const parent = parentSnap.data();
    const teacher = teacherSnap.data();

    if (!student || student.isDeleted === true) {
      throw new HttpsError("not-found", "That student is not on the roll.");
    }
    if (!parent || parent.role !== "parent") {
      throw new HttpsError("not-found", "That parent account was not found.");
    }
    if (!teacher || teacher.role !== "faculty") {
      throw new HttpsError("not-found", "That teacher account was not found.");
    }

    if (!isLinkedParent(parent.linkedStudentIds, studentId)) {
      throw new HttpsError(
        "permission-denied",
        "That parent is not linked to that student."
      );
    }

    const assignments = assignmentsSnap.docs.map((doc) => doc.data());
    if (!teachesSection(assignments, teacherUid, (student.section as string) ?? "")) {
      // Named plainly rather than as a generic denial: a parent looking
      // for a teacher who has since stopped teaching their child should
      // learn that, not conclude the app is broken.
      throw new HttpsError(
        "permission-denied",
        `${teacher.firstName ?? "That teacher"} does not teach ${
          student.firstName ?? "this student"
        }'s class.`
      );
    }

    const id = conversationId(teacherUid, parentUid, studentId);
    const ref = db.doc(FirestorePaths.conversationDoc(schoolId, id));
    const existing = await ref.get();
    if (existing.exists) {
      return {conversationId: id, created: false};
    }

    await ref.set({
      id,
      schoolId,
      // The field every read rule is built on. An array rather than two
      // named fields so one `array-contains` query serves both sides.
      participantUids: [teacherUid, parentUid],
      teacherUid,
      teacherName: `${teacher.firstName ?? ""} ${teacher.lastName ?? ""}`.trim(),
      parentUid,
      parentName: `${parent.firstName ?? ""} ${parent.lastName ?? ""}`.trim(),
      studentId,
      studentName: `${student.firstName ?? ""} ${student.lastName ?? ""}`.trim(),
      section: student.section ?? "",
      lastMessage: null,
      lastMessageAt: null,
      lastSenderUid: null,
      // Per participant, so each side's list can show its own badge
      // without reading the other's messages.
      unread: {[teacherUid]: 0, [parentUid]: 0},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: callerUid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: callerUid,
      isDeleted: false,
    });

    return {conversationId: id, created: true};
  }
);
