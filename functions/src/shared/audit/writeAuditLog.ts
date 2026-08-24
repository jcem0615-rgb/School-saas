import * as admin from "firebase-admin";
import {FirestorePaths} from "../firestore-paths";

export interface AuditLogEntry {
  schoolId: string;
  userId: string;
  userRole: string;
  userName: string;
  module: string;
  action: string;
  targetCollection: string;
  targetId: string;
  previousValue?: Record<string, unknown> | null;
  newValue?: Record<string, unknown> | null;
  device?: string | null;
  ipAddress?: string | null;
  success: boolean;
  remarks?: string | null;
}

/**
 * Writes an immutable audit log entry. This is the ONLY code path that
 * writes to schools/{schoolId}/auditLog -- Firestore Security Rules deny
 * all client writes to that collection outright (see firestore.rules),
 * so every entry that exists was genuinely written by trusted server code,
 * which is the whole point of the audit trail for a paying customer.
 */
export async function writeAuditLog(entry: AuditLogEntry): Promise<void> {
  const db = admin.firestore();
  const ref = db.collection(FirestorePaths.auditLog(entry.schoolId)).doc();
  await ref.set({
    id: ref.id,
    schoolId: entry.schoolId,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    userId: entry.userId,
    userRole: entry.userRole,
    userName: entry.userName,
    module: entry.module,
    action: entry.action,
    targetCollection: entry.targetCollection,
    targetId: entry.targetId,
    previousValue: entry.previousValue ?? null,
    newValue: entry.newValue ?? null,
    device: entry.device ?? null,
    ipAddress: entry.ipAddress ?? null,
    success: entry.success,
    remarks: entry.remarks ?? null,
  });
}
