import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {deliver} from "../../shared/notify/deliver";

/**
 * Pushes a student's emergency alert to their class adviser and their
 * parents.
 *
 * Everything about who gets notified is resolved here, server-side, from
 * records the student cannot edit: the adviser comes from the section's
 * advisory assignment, the parents from the linked-student list on their
 * own user documents. A client-supplied recipient list would let a
 * student direct an alert anywhere, or nowhere.
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

    // The section's adviser. There should be exactly one; if a school has
    // set two by mistake, notifying both is the right failure.
    if (section) {
      const advisers = await db
        .collection(FirestorePaths.teacherAssignments(schoolId))
        .where("section", "==", section)
        .where("isAdviser", "==", true)
        .get();
      for (const doc of advisers.docs) {
        const teacherId = doc.data().teacherId as string | undefined;
        if (teacherId) recipientUids.add(teacherId);
      }
    }

    // Parents and guardians linked to this student.
    const parents = await db
      .collection(FirestorePaths.users(schoolId))
      .where("role", "==", "parent")
      .where("linkedStudentIds", "array-contains", studentId)
      .get();
    for (const doc of parents.docs) recipientUids.add(doc.id);

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
