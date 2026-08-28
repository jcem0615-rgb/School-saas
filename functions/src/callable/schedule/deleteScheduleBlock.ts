import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface DeleteScheduleBlockData {
  schoolId: string;
  blockId: string;
}

const ALLOWED_ROLES = ["director", "principal", "admin"];

/**
 * Takes one class off the timetable.
 *
 * A soft delete, like every other removal in this system: the audit log
 * records who dropped a class from the week, and a timetable that can be
 * silently emptied is one nobody can reconstruct after an argument about
 * whether a class was ever scheduled.
 */
export const deleteScheduleBlock = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<DeleteScheduleBlockData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {schoolId, blockId} = request.data;
    if (!schoolId || !blockId) {
      throw new HttpsError("invalid-argument", "Missing class.");
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();
    const ref = db.doc(FirestorePaths.scheduleBlockDoc(schoolId, blockId));
    const snapshot = await ref.get();
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "That class is no longer on the timetable.");
    }
    const block = snapshot.data()!;

    await ref.update({
      isDeleted: true,
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "",
      module: "schedule",
      action: "delete_schedule_block",
      targetCollection: FirestorePaths.scheduleBlocks(schoolId),
      targetId: blockId,
      previousValue: {
        subject: block.subject,
        section: block.section,
        dayOfWeek: block.dayOfWeek,
        startMinute: block.startMinute,
      },
      success: true,
      remarks: `${block.subject ?? "A class"} for ${block.section ?? "a section"}`,
    });

    return {blockId};
  }
);
