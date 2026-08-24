import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";

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
 * Best-effort by design. If a device token is stale or a parent never
 * enabled notifications, the alert is still a document on the staff
 * Emergency Alerts screen -- that list is the dependable channel and this
 * is the fast one. Never let a push failure throw, because a retried
 * trigger would re-notify everyone.
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

    if (recipientUids.size === 0) return;

    const tokenSnaps = await Promise.all(
      [...recipientUids].map((uid) =>
        db.collection(`${FirestorePaths.userDoc(schoolId, uid)}/deviceTokens`).get()
      )
    );

    const tokens: string[] = [];
    const tokenRefs = new Map<string, FirebaseFirestore.DocumentReference>();
    for (const snap of tokenSnaps) {
      for (const doc of snap.docs) {
        tokens.push(doc.id);
        tokenRefs.set(doc.id, doc.ref);
      }
    }
    if (tokens.length === 0) return;

    const message = (data.message as string) ?? "";
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `Emergency alert: ${studentName}`,
        body: message.length > 0 ? message : `${studentName} (${section ?? ""}) needs help.`,
      },
      data: {
        type: "emergency",
        alertId: event.params.alertId,
        studentId,
        schoolId,
      },
      // High priority on both platforms: this is the one notification in
      // this app that must not wait for a batching window.
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}, headers: {"apns-priority": "10"}},
      webpush: {
        notification: {icon: "/icons/Icon-192.png", requireInteraction: true},
        fcmOptions: {link: "/#/emergency-alerts"},
        headers: {Urgency: "high"},
      },
    });

    // Prune dead tokens, same as the announcement fan-out.
    const stale: Promise<unknown>[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        const ref = tokenRefs.get(tokens[index]);
        if (ref) stale.push(ref.delete());
      }
    });
    await Promise.all(stale);
  }
);
