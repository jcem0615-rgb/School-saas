import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface OpenShiftData {
  schoolId: string;
  openingFloat: number;
  notes?: string;
}

/**
 * Who handles cash. The same pair that may record a payment -- faculty,
 * staff and guidance have no business at the window.
 */
const CASHIER_ROLES = ["admin", "registrar"];

/**
 * Opens a drawer.
 *
 * A shift is a window of time over this cashier's own collections, not
 * a label stuck on each receipt: nothing has to remember to tag a
 * payment, which means nothing can forget to. Opening one is therefore
 * just recording when it started and what was in it.
 *
 * The float is counted by the person opening the drawer. A float taken
 * on trust is a discrepancy that was always there and nobody can date.
 */
export const openCashierShift = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<OpenShiftData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, openingFloat, notes} = request.data ?? {};

    if (!schoolId || typeof openingFloat !== "number") {
      throw new HttpsError("invalid-argument", "Missing the opening float.");
    }
    requireSameSchool(callerClaims, schoolId);
    if (!CASHIER_ROLES.includes(callerClaims.role)) {
      throw new HttpsError(
        "permission-denied",
        "Only a cashier can open a drawer."
      );
    }
    if (!Number.isFinite(openingFloat) || openingFloat < 0) {
      throw new HttpsError("invalid-argument", "A float cannot be a negative amount.");
    }

    const db = admin.firestore();
    const uid = request.auth!.uid;

    // Two drawers open for one person means every receipt belongs to
    // both and the reckoning is meaningless.
    const alreadyOpen = await db
      .collection(FirestorePaths.cashierShifts(schoolId))
      .where("cashierUid", "==", uid)
      .where("closedAt", "==", null)
      .limit(1)
      .get();
    if (!alreadyOpen.empty) {
      throw new HttpsError(
        "failed-precondition",
        "There is already a drawer open. Close it before opening another."
      );
    }

    const name = (request.auth!.token.name as string) ?? "Unknown";
    const ref = db.collection(FirestorePaths.cashierShifts(schoolId)).doc();
    await ref.set({
      id: ref.id,
      schoolId,
      cashierUid: uid,
      cashierName: name,
      openedAt: admin.firestore.FieldValue.serverTimestamp(),
      openingFloat,
      // Written as nulls rather than left absent: the open-shift query
      // above matches on closedAt == null, and Firestore cannot match a
      // document that does not carry the field.
      closedAt: null,
      countedAmount: null,
      expectedAmount: null,
      varianceNote: null,
      closedByName: null,
      journalEntryId: null,
      notes: notes?.trim() || null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: uid,
      isDeleted: false,
    });

    await writeAuditLog({
      schoolId,
      userId: uid,
      userRole: callerClaims.role,
      userName: name,
      module: "cashiering",
      action: "shift_opened",
      targetCollection: FirestorePaths.cashierShifts(schoolId),
      targetId: ref.id,
      newValue: {openingFloat},
      success: true,
    });

    return {shiftId: ref.id};
  }
);
