import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {audienceIncludes, readAudience} from "../../shared/announcements/audience";
import {deliver} from "../../shared/notify/deliver";

/**
 * Puts a new announcement in the inbox of everyone it is addressed to,
 * and on their phones.
 *
 * The audience is resolved *here*, server-side, not trusted from the
 * client. The list filter in the app decides what a screen shows; this
 * decides whose phone rings at 5am about a typhoon suspension, and the
 * two failure modes are not comparable. A notification cannot be unsent.
 *
 * Draft/unpublished announcements do not exist for this collection --
 * every announcement is live the moment it is written -- so creation is
 * the right hook. Edits deliberately do not re-notify: correcting a typo
 * in a suspension notice should not buzz eight hundred phones a second
 * time.
 */
export const onAnnouncementCreated = onDocumentCreated(
  {region: "asia-southeast1", document: "schools/{schoolId}/announcements/{announcementId}"},
  async (event) => {
    const schoolId = event.params.schoolId;
    const data = event.data?.data();
    if (!data) return;
    if (data.isDeleted === true) return;

    const audience = readAudience(data);
    if (!audience.all && audience.roles.length === 0) {
      // Addressed to nobody. The editor disables Post in this state; this
      // is the second line, for anything written straight to Firestore.
      return;
    }

    const db = admin.firestore();

    // Every active user in the school, filtered in memory by the same
    // rule the app's list uses. A role-based `where in` query cannot
    // express "all OR one of these roles" in one pass, and a school's
    // user count is in the hundreds, not the millions.
    const usersSnap = await db.collection(FirestorePaths.users(schoolId)).get();
    const recipients = usersSnap.docs
      .filter((doc) => {
        const user = doc.data();
        if (user.status !== "active") return false;
        return audienceIncludes(audience, user.role as string);
      })
      .map((doc) => doc.id);

    await deliver({
      schoolId,
      recipientUids: recipients,
      kind: "announcement",
      title: (data.title as string) ?? "Announcement",
      body: (data.body as string) ?? "",
      link: "/notifications",
      sourceId: event.params.announcementId,
      data: {announcementId: event.params.announcementId},
    });
  }
);
