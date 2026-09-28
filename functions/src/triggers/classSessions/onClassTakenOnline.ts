import * as admin from "firebase-admin";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {deliver} from "../../shared/notify/deliver";
import {isMeetingRoom} from "../../shared/meeting/room";
import {onlineClassBody, onlineClassTitle} from "../../shared/notify/onlineClassMessage";

/**
 * Tells a section that their lesson has started.
 *
 * ## Why this is not optional
 *
 * A class held in a room announces itself: the bell goes, everybody
 * walks in. A class held online announces itself to whoever happens to
 * have the app open, which at ten past eight on a Tuesday is nobody.
 * Without this, "we are online today" has to be arranged in advance
 * through a channel the school does not control -- a group chat, a
 * parent relaying a message -- and the pupils who miss it are the ones
 * who were already going to miss it.
 *
 * ## Why a trigger and not the callable
 *
 * `setClassSessionMode` already writes the room onto every mark in the
 * class, one batch at a time. Fanning a notification out from inside it
 * would put the slowest part of this in front of the teacher who is
 * waiting to start, and a failure there would fail taking the class
 * online -- which is the one thing that must not fail. A trigger runs
 * after the fact, retries on its own, and cannot hold the lesson up.
 *
 * ## Who is told
 *
 * The students on the register, and only them. Not the parents: a
 * lesson starting is a thing that happens four times a day and a parent
 * buzzed each time stops reading any of them. Not the teacher, who
 * pressed the button.
 *
 * A student with no login yet is silently skipped -- the registrar has
 * not issued them one, and there is nowhere to send it.
 *
 * ## Where tapping it lands
 *
 * `/join?school=...&class=...` -- the same address the teacher's
 * invitation link uses, which is already a route in the app. Tapping the
 * notification and following a forwarded link end up in exactly the same
 * place, asking for the same code, checked by the same four locks. The
 * link is an address in both cases and never a permission.
 */
export const onClassTakenOnline = onDocumentUpdated(
  {region: "asia-southeast1", document: "schools/{schoolId}/classSessions/{sessionId}"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (after.isDeleted === true) return;

    // The edge, not the state. This document is updated on every mark a
    // teacher changes; only the moment a room appears is news, and only
    // once -- otherwise every register edit for the rest of the lesson
    // would buzz the class again.
    const wasOnline = isMeetingRoom(before.meetingRoom);
    const isOnline = isMeetingRoom(after.meetingRoom);
    if (wasOnline || !isOnline) return;

    // A room on a register that has already finished is a door left
    // open, and telling a class to join a lesson that is over is worse
    // than saying nothing.
    if (after.status === "closed") return;

    const schoolId = event.params.schoolId;
    const sessionId = event.params.sessionId;

    const recipients = await studentsOnTheRegister(schoolId, sessionId);
    if (recipients.length === 0) return;

    const subject = (after.subject as string) ?? "";
    const section = (after.section as string) ?? "";

    await deliver({
      schoolId,
      recipientUids: recipients,
      kind: "general",
      title: onlineClassTitle(subject),
      body: onlineClassBody(subject, section),
      // The same address as the teacher's invitation link, and a route
      // this app already has.
      link: `/join?school=${schoolId}&class=${sessionId}`,
      // The room, not just the session: a class brought back in person
      // and taken online again in the same lesson is a second thing
      // worth being told, and a sourceId of the session alone would
      // make the inbox treat it as a duplicate of the first.
      sourceId: `${sessionId}:${after.meetingRoom as string}`,
      data: {sessionId, schoolId},
      // Not urgent. A lesson starting is expected; ringing through a
      // do-not-disturb is for an emergency and this is not one.
    });
  }
);

/**
 * The accounts of the students on this register.
 *
 * Off the marks rather than off the section, because the register is
 * what the lesson is actually for: a child who transferred out this
 * morning has no line on it and should not be told to join, and one who
 * transferred in is on it and should.
 *
 * `userId` is on the student record, not on the mark, so this is two
 * reads. A student without one has no login yet and is skipped.
 */
async function studentsOnTheRegister(
  schoolId: string,
  sessionId: string
): Promise<string[]> {
  const db = admin.firestore();

  const marks = await db
    .collection(FirestorePaths.subjectAttendance(schoolId))
    .where("sessionId", "==", sessionId)
    .get();

  const studentIds = [
    ...new Set(
      marks.docs
        .map((doc) => doc.data().studentId as string | undefined)
        .filter((id): id is string => !!id)
    ),
  ];
  if (studentIds.length === 0) return [];

  // `in` takes thirty at a time, and a section is rarely more than
  // sixty -- but a batched read is still two queries rather than sixty.
  const uids = new Set<string>();
  for (let i = 0; i < studentIds.length; i += 30) {
    const page = studentIds.slice(i, i + 30);
    const snap = await db
      .collection(FirestorePaths.students(schoolId))
      .where(admin.firestore.FieldPath.documentId(), "in", page)
      .get();
    for (const doc of snap.docs) {
      const userId = doc.data().userId as string | undefined;
      if (userId) uids.add(userId);
    }
  }
  return [...uids];
}
