import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {audienceIncludes, readAudience} from "../../shared/announcements/audience";

/**
 * Pushes a new announcement to the phones of the roles it is addressed to.
 *
 * The audience is resolved *here*, server-side, not trusted from the
 * client. The list filter in the app decides what a screen shows; this
 * decides whose phone rings at 5am about a typhoon suspension, and the
 * two failure modes are not comparable. A notification cannot be
 * unsent.
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
    const recipients = usersSnap.docs.filter((doc) => {
      const user = doc.data();
      if (user.status !== "active") return false;
      return audienceIncludes(audience, user.role as string);
    });

    if (recipients.length === 0) return;

    // Tokens live in a per-user subcollection rather than an array on the
    // user document: users/{uid} is readable by everyone in the school,
    // and a device token in there would be readable by every colleague.
    const tokenDocs = await Promise.all(
      recipients.map((doc) => doc.ref.collection("deviceTokens").get())
    );

    const tokens: string[] = [];
    const tokenOwner = new Map<string, FirebaseFirestore.DocumentReference>();
    for (const snap of tokenDocs) {
      for (const tokenDoc of snap.docs) {
        // The document ID *is* the token -- that is what makes
        // registering the same device twice idempotent.
        tokens.push(tokenDoc.id);
        tokenOwner.set(tokenDoc.id, tokenDoc.ref);
      }
    }
    if (tokens.length === 0) return;

    const title = (data.title as string) ?? "Announcement";
    const body = (data.body as string) ?? "";

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title,
        // A push preview is a lock-screen line, not a document. The full
        // text is one tap away in the app.
        body: body.length > 180 ? `${body.slice(0, 177)}...` : body,
      },
      data: {
        type: "announcement",
        announcementId: event.params.announcementId,
        schoolId,
      },
      webpush: {
        notification: {icon: "/icons/Icon-192.png"},
        fcmOptions: {link: "/#/announcements"},
      },
    });

    // Prune tokens FCM tells us are dead. Without this the token list
    // grows forever with every reinstalled app and cleared browser, and
    // each send wastes a slot on a device that will never receive again.
    const stale: Promise<unknown>[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const code = result.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument"
      ) {
        const ref = tokenOwner.get(tokens[index]);
        if (ref) stale.push(ref.delete());
      }
    });
    await Promise.all(stale);
  }
);
