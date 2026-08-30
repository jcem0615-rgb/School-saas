import * as admin from "firebase-admin";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {FirestorePaths} from "../../shared/firestore-paths";
import {previewOf} from "../../shared/messaging/conversation";
import {deliver} from "../../shared/notify/deliver";

/**
 * Keeps the conversation summary honest, and tells the other person.
 *
 * Both server-side, and for the same reason: the summary is what each
 * side's list is sorted and badged by, and a client that could write it
 * could mark its own messages read for the other person, or push its
 * thread to the top of their list without saying anything. Clients write
 * messages; nothing else.
 *
 * Never throws. A failed notification must not fail the write that
 * caused it -- a thrown trigger is a retried trigger, and a retried
 * fan-out sends the same message twice.
 */
export const onMessageCreated = onDocumentCreated(
  {
    region: "asia-southeast1",
    document: "schools/{schoolId}/conversations/{conversationId}/messages/{messageId}",
  },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;

    const schoolId = event.params.schoolId;
    const conversationId = event.params.conversationId;
    const senderUid = message.senderUid as string | undefined;
    const text = (message.text as string) ?? "";
    if (!senderUid) return;

    const db = admin.firestore();
    const conversationRef = db.doc(
      FirestorePaths.conversationDoc(schoolId, conversationId)
    );
    const snap = await conversationRef.get();
    const conversation = snap.data();
    if (!conversation) return;

    const participants = (conversation.participantUids as string[]) ?? [];
    const recipients = participants.filter((uid) => uid !== senderUid);

    await conversationRef.update({
      lastMessage: previewOf(text),
      lastMessageAt: message.sentAt ?? admin.firestore.FieldValue.serverTimestamp(),
      lastSenderUid: senderUid,
      // Only the other side's count moves. Incremented rather than set,
      // so two messages arriving at once do not overwrite each other's
      // increment.
      ...Object.fromEntries(
        recipients.map((uid) => [
          `unread.${uid}`,
          admin.firestore.FieldValue.increment(1),
        ])
      ),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    if (recipients.length === 0) return;

    const senderName = (message.senderName as string) ?? "Someone";
    const about = (conversation.studentName as string) ?? "";

    await deliver({
      schoolId,
      recipientUids: recipients,
      kind: "general",
      // Names the child, because a teacher with thirty families and a
      // parent with four teachers both need to know which conversation
      // rang before they open it.
      title: about ? `${senderName} · about ${about}` : senderName,
      body: previewOf(text, 180),
      link: "/messages",
      // One notification per message. A thread the other person is
      // sitting in still gets an inbox item, which is the price of the
      // inbox being a record of what was sent rather than of what was
      // missed.
      sourceId: `${conversationId}:${event.params.messageId}`,
      data: {conversationId},
    });
  }
);
