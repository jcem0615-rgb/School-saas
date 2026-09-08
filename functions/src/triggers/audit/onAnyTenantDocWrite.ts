import * as admin from "firebase-admin";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {classifyAction} from "../../shared/audit/classifyAction";

/**
 * Fires on every write to any direct subcollection of a school
 * (schools/{schoolId}/{collectionId}/{docId}) and records it to the
 * tenant's audit log automatically.
 *
 * This is what lets modules like Announcements, Meetings, Approvals, and
 * Expenses allow direct client writes (gated by firestore.rules) without
 * each one needing its own callable function just to satisfy the "every
 * action must be logged" requirement -- the trigger does it uniformly.
 *
 * Excluded collections are ones with their own bespoke audit handling
 * (users -- audited inside the provisioning callables) or ones that would
 * cause runaway/self-referential writes (auditLog itself, notifications,
 * counters -- high write volume, low audit value).
 */
const EXCLUDED_COLLECTIONS = new Set(["auditLog", "notifications", "counters", "users"]);

/**
 * Collections whose *content* must not be copied into the log, even
 * though the fact of the write is worth recording.
 *
 * The trail is read school-wide by the Director and the Admin. Copying a
 * document into an entry therefore makes that document readable by both
 * of them, whatever the collection's own read rule says -- and for one
 * collection the read rule says the opposite in as many words.
 *
 * `conversations` carries `lastMessage`, a preview of what a parent last
 * said to a teacher, rewritten on every message. Its rule says nobody
 * but the two participants may read a thread -- "not an admin, not the
 * director" -- and that a school needing to see one has a lawful-request
 * path "and an audit trail, not a back door". The audit trail was the
 * back door.
 *
 * The entry is still written: who touched which thread, and when. Only
 * the values are withheld, and the entry says so rather than looking
 * like a document with nothing in it.
 *
 * The invariant, for anything added here later: the audit log must never
 * carry content that its own readers could not otherwise read.
 */
const CONTENT_WITHHELD = new Set(["conversations"]);

export const onAnyTenantDocWrite = onDocumentWritten(
  {document: "schools/{schoolId}/{collectionId}/{docId}", region: "asia-southeast1"},
  async (event) => {
    const {schoolId, collectionId, docId} = event.params;
    if (EXCLUDED_COLLECTIONS.has(collectionId)) return;

    // `?? null` matters: DocumentSnapshot.data() is typed as possibly
    // undefined, and classifyAction distinguishes null (no document) from a
    // document that exists -- passing undefined through would not compile,
    // and coercing it to an empty object would turn a delete into an update.
    const before = event.data?.before?.exists ? event.data.before.data() ?? null : null;
    const after = event.data?.after?.exists ? event.data.after.data() ?? null : null;

    const action = classifyAction(before, after);

    // Prefer the acting user recorded on the document itself
    // (updatedBy/createdBy, set by the client at write time) over
    // event.data metadata, since Firestore triggers don't carry the
    // caller's auth context directly.
    //
    // `before` is consulted too, and only a delete reaches it: a hard
    // delete has no `after`, so there is nothing left to read the actor
    // from. Falling straight through to "unknown" made this answer "who
    // deleted it?" with the one word the trail exists to avoid -- on the
    // single action where the answer matters most and is least
    // recoverable from anywhere else. The last account to touch the
    // document is not proof of who removed it, which is why the entry
    // says as much in its remarks.
    const actingUid =
      (after?.updatedBy as string) ??
      (after?.createdBy as string) ??
      (before?.updatedBy as string) ??
      (before?.createdBy as string) ??
      "unknown";

    let actingUserRole = "unknown";
    let actingUserName = "Unknown";
    try {
      const userSnap = await admin.firestore().doc(`schools/${schoolId}/users/${actingUid}`).get();
      if (userSnap.exists) {
        const u = userSnap.data()!;
        actingUserRole = u.role ?? "unknown";
        actingUserName = `${u.firstName ?? ""} ${u.lastName ?? ""}`.trim() || "Unknown";
      }
    } catch {
      // Best-effort enrichment only -- never block the audit write on this.
    }

    const withheld = CONTENT_WITHHELD.has(collectionId);
    const remarks = withheld ?
      "Content not recorded: this collection is readable only by the people " +
        "named on the document, and the audit log is not." :
      action === "delete" ?
        "Deleted. The account named is the last one to have written this " +
          "document, which is the closest the record can get." :
        null;

    await writeAuditLog({
      schoolId,
      userId: actingUid,
      userRole: actingUserRole,
      userName: actingUserName,
      module: collectionId,
      action,
      targetCollection: `schools/${schoolId}/${collectionId}`,
      targetId: docId,
      previousValue: withheld ? null : before,
      newValue: withheld ? null : after,
      success: true,
      remarks,
    });
  }
);
