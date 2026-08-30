import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {deliver} from "../../shared/notify/deliver";
import {
  formatSummonsWhen,
  summonsCancelledBody,
  summonsIssuedBody,
} from "../../shared/notify/summonsMessage";

/**
 * Tells a student, and their parents, that they have been called to the
 * guidance office -- and tells them again if it is called off.
 *
 * The summons has always been visible to both: firestore.rules opens it
 * to the student's own account and to any parent linked to them, which
 * is the deliberate difference between a summons and the counseling
 * notes behind it. But visible is not the same as told. A family found
 * out by opening the app on the right day and noticing, and the one
 * thing a summons has that a grade does not is a date it is too late to
 * be useful after.
 *
 * Notified on two transitions and no others:
 *
 *   * created -- "you are asked to come in";
 *   * cancelled -- "you are not, after all", which matters more than the
 *     first one: a family that rearranges a working day around an
 *     appointment should not turn up to a cancelled one.
 *
 * Completed is deliberately silent. The student was there; they know.
 * An edit to the reason or the date is silent too, for now, because the
 * office reworking its own wording should not buzz a family each time --
 * a moved date is issued as a new summons.
 *
 * onDocumentWritten rather than onDocumentCreated because a status
 * change is an update, and both live here so the two paths cannot drift
 * apart.
 */
export const onSummonsWritten = onDocumentWritten(
  {region: "asia-southeast1", document: "schools/{schoolId}/summons/{summonsId}"},
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!after) return; // hard delete; the collection forbids them anyway
    if (after.isDeleted === true) return;

    const schoolId = event.params.schoolId;
    const summonsId = event.params.summonsId;

    const created = !before;
    const cancelled =
      !!before && before.status !== "cancelled" && after.status === "cancelled";
    if (!created && !cancelled) return;

    const studentId = after.studentId as string | undefined;
    if (!studentId) return;

    const recipients = await familyOf(schoolId, studentId);
    if (recipients.length === 0) return;

    const when = formatSummonsWhen(toDate(after.scheduledDate));
    const studentName = (after.studentName as string) ?? "";
    const reason = (after.reason as string) ?? "";

    if (cancelled) {
      await deliver({
        schoolId,
        recipientUids: recipients,
        kind: "summons",
        title: "Guidance appointment cancelled",
        body: summonsCancelledBody(studentName, when),
        link: "/notifications",
        // Distinct from the issuing notification, or the inbox would
        // treat the cancellation as a duplicate of it and drop it.
        sourceId: `${summonsId}:cancelled`,
        data: {summonsId, studentId},
      });
      return;
    }

    await deliver({
      schoolId,
      recipientUids: recipients,
      kind: "summons",
      title: "Guidance office appointment",
      body: summonsIssuedBody(studentName, when, reason),
      link: "/notifications",
      sourceId: summonsId,
      data: {summonsId, studentId},
    });
  }
);

/**
 * The student's own account, plus every parent linked to them.
 *
 * Resolved here, server-side, from records neither of them can edit. A
 * student record without a `userId` is one the registrar has not issued
 * a login for yet -- the parents are still told, which is the point.
 */
async function familyOf(schoolId: string, studentId: string): Promise<string[]> {
  const db = admin.firestore();
  const uids = new Set<string>();

  const [student, parents] = await Promise.all([
    db.doc(FirestorePaths.studentDoc(schoolId, studentId)).get(),
    db
      .collection(FirestorePaths.users(schoolId))
      .where("role", "==", "parent")
      .where("linkedStudentIds", "array-contains", studentId)
      .get(),
  ]);

  const studentUid = student.data()?.userId as string | undefined;
  if (studentUid) uids.add(studentUid);
  for (const doc of parents.docs) {
    if (doc.data().status === "active") uids.add(doc.id);
  }
  return [...uids];
}

/** A Firestore Timestamp, a Date, or neither. */
function toDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}
