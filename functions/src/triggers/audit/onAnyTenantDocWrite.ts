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
    const actingUid = (after?.updatedBy as string) ?? (after?.createdBy as string) ?? "unknown";

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

    await writeAuditLog({
      schoolId,
      userId: actingUid,
      userRole: actingUserRole,
      userName: actingUserName,
      module: collectionId,
      action,
      targetCollection: `schools/${schoolId}/${collectionId}`,
      targetId: docId,
      previousValue: before,
      newValue: after,
      success: true,
    });
  }
);
