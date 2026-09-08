import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {normalizeSection} from "../../shared/sections";
import {deliver} from "../../shared/notify/deliver";

/**
 * Who the school tells when a student presses the button.
 *
 * The adviser knows the child and is usually nearest to them. They are
 * not enough on their own: a section with no adviser set, an adviser on
 * leave, or a section name typed a shade differently on the assignment
 * than on the student record, and the alert reaches nobody at the school
 * at all -- only the parents, who are not in the building.
 *
 * So the roles whose job this is are told as well, every time. It is a
 * small, bounded set in any school, and over-telling is the right
 * failure for the one notification in this app that somebody may be in
 * danger behind. Every teacher in the school would be the wrong answer;
 * nobody is a worse one.
 */
const RESPONDER_ROLES = ["guidance", "director", "principal", "admin"];

/**
 * Pushes a student's emergency alert to the people who can go and help.
 *
 * Everything about who gets notified is resolved here, server-side, from
 * records the student cannot edit: the adviser comes from the section's
 * advisory assignment, the responders from their role, the parents from
 * the linked-student list on their own user documents. A client-supplied
 * recipient list would let a student direct an alert anywhere, or
 * nowhere.
 *
 * Best-effort on the push half by design. If a device token is stale or a
 * parent never enabled notifications, the alert is still an inbox item
 * and still a document on the staff Emergency Alerts screen -- those are
 * the dependable channels and the push is the fast one.
 */
export const onEmergencyAlertCreated = onDocumentCreated(
  {region: "asia-southeast1", document: "schools/{schoolId}/emergencyAlerts/{alertId}"},
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const schoolId = event.params.schoolId;
    const studentId = data.studentId as string | undefined;
    const section = data.section as string | undefined;
    const studentName = (data.studentName as string) ?? "A student";
    if (!studentId) return;

    const db = admin.firestore();
    const recipientUids = new Set<string>();

    const [assignmentsSnap, respondersSnap, parentsSnap] = await Promise.all([
      // Read whole and matched in memory rather than queried by section.
      // `where("section", "==", ...)` matches exactly, and a section name
      // is typed by hand on the student record and again on the teacher's
      // assignment -- so "Grade 10 - Rizal" against "Grade 10 - rizal "
      // silently means no adviser is found. That is a bad way to lose a
      // notification anywhere; here it is the worst place in the app.
      section ?
        db.collection(FirestorePaths.teacherAssignments(schoolId)).get() :
        Promise.resolve(null),
      db
        .collection(FirestorePaths.users(schoolId))
        .where("role", "in", RESPONDER_ROLES)
        .get(),
      db
        .collection(FirestorePaths.users(schoolId))
        .where("role", "==", "parent")
        .where("linkedStudentIds", "array-contains", studentId)
        .get(),
    ]);

    // The section's adviser. There should be exactly one; if a school has
    // set two by mistake, notifying both is the right failure.
    if (assignmentsSnap && section) {
      const wanted = normalizeSection(section);
      for (const doc of assignmentsSnap.docs) {
        const assignment = doc.data();
        if (assignment.isAdviser !== true) continue;
        if (normalizeSection(assignment.section as string) !== wanted) continue;
        const teacherId = assignment.teacherId as string | undefined;
        if (teacherId) recipientUids.add(teacherId);
      }
    }

    // Guidance and the office. Filtered in memory rather than with two
    // more `where` clauses, which would want a composite index for a
    // query this small.
    for (const doc of respondersSnap.docs) {
      const user = doc.data();
      if (user.status !== "active" || user.isDeleted === true) continue;
      recipientUids.add(doc.id);
    }

    // Parents and guardians linked to this student.
    for (const doc of parentsSnap.docs) recipientUids.add(doc.id);

    const message = (data.message as string) ?? "";
    await deliver({
      schoolId,
      recipientUids: [...recipientUids],
      kind: "emergency",
      title: `Emergency alert: ${studentName}`,
      body: message.length > 0 ? message : `${studentName} (${section ?? ""}) needs help.`,
      link: "/notifications",
      sourceId: event.params.alertId,
      data: {alertId: event.params.alertId, studentId},
      // The one notification in this app that must not wait for a
      // batching window.
      urgent: true,
    });
  }
);
