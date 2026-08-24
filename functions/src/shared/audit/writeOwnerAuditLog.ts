import * as admin from "firebase-admin";
import {FirestorePaths} from "../firestore-paths";

export interface OwnerAuditLogEntry {
  /** The signed-in Owner who performed the action. */
  actorUid: string;
  actorEmail?: string | null;
  /** Dotted verb, e.g. "owner.bootstrapped", "school.created". */
  action: string;
  /** What was acted on: a schoolId, a uid. */
  targetType: string;
  targetId: string;
  details?: Record<string, unknown> | null;
  success?: boolean;
}

/**
 * Writes an immutable platform-level audit entry.
 *
 * The tenant audit log next door is school-scoped -- it takes a schoolId
 * and writes under schools/{schoolId}/auditLog. The Owner belongs to no
 * school, and the acts that matter most here (claiming the owner role,
 * standing up a new school) happen before any tenant exists to file them
 * under. firestore.rules already reserves platform_owner_audit_log as
 * readable by the Owner and writable by nobody, so entries can only come
 * from server code holding the Admin SDK, which is what makes the trail
 * worth anything.
 */
export async function writeOwnerAuditLog(entry: OwnerAuditLogEntry): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection(FirestorePaths.platformOwnerAuditLog).doc();
  await ref.set({
    id: ref.id,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    actorUid: entry.actorUid,
    actorEmail: entry.actorEmail ?? null,
    action: entry.action,
    targetType: entry.targetType,
    targetId: entry.targetId,
    details: entry.details ?? null,
    success: entry.success ?? true,
  });
}
