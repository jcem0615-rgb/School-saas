import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {
  MOVEMENT_LABELS,
  MovementError,
  applyMovement,
  validateMovement,
} from "../../shared/inventory/movement";

interface RecordMovementData {
  schoolId: string;
  itemId: string;
  kind: string;
  quantity: number;
  issuedTo?: string;
  reference?: string;
  note?: string;
}

/** The roles that actually keep the stock room, matching firestore.rules. */
const STOCK_ROLES = ["admin", "staff"];

/**
 * Moves something in or out of the stock room.
 *
 * The item's `quantityOnHand` is read, checked and written inside one
 * transaction, and firestore.rules now refuses any client write to that
 * field -- so the only thing that can move a count is a movement, which
 * is what makes the log worth keeping.
 *
 * This used to be a client transaction. It re-read the item, which was
 * the right instinct, and then never re-checked anything against what it
 * read: the "would this go below zero" test lived on the device, against
 * the copy the screen was holding. Two people issuing the last two
 * projectors at once both passed it and the shelf went to -2 -- the case
 * the transaction was written for, with a comment saying so.
 */
export const recordInventoryMovement = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RecordMovementData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, itemId} = request.data ?? {};

    if (!schoolId || !itemId) {
      throw new HttpsError("invalid-argument", "Which item, in which school?");
    }
    requireSameSchool(callerClaims, schoolId);
    requireRole(callerClaims, STOCK_ROLES);

    let movement;
    try {
      movement = validateMovement(request.data);
    } catch (error) {
      if (error instanceof MovementError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const db = admin.firestore();
    const itemRef = db.doc(FirestorePaths.inventoryDoc(schoolId, itemId));
    const movementRef = db.collection(FirestorePaths.inventoryTransactions(schoolId)).doc();

    let itemName = "";
    let quantityBefore = 0;
    let quantityAfter = 0;

    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(itemRef);
        if (!snap.exists || snap.data()?.isDeleted === true) {
          throw new HttpsError("not-found", "That item is no longer on file.");
        }
        const data = snap.data() ?? {};
        itemName = (data.name as string) ?? "";
        quantityBefore = Number(data.quantityOnHand);
        if (!Number.isFinite(quantityBefore)) quantityBefore = 0;
        // Checked here, against what is actually on file, and not
        // against anything the caller sent or a screen was showing.
        quantityAfter = applyMovement(quantityBefore, movement);

        tx.create(movementRef, {
          id: movementRef.id,
          schoolId,
          itemId,
          itemName,
          kind: movement.kind,
          quantity: movement.quantity,
          issuedTo: movement.issuedTo,
          reference: movement.reference,
          note: movement.note,
          recordedBy: request.auth!.uid,
          recordedByName: (request.auth!.token.name as string) ?? "Unknown",
          recordedAt: admin.firestore.FieldValue.serverTimestamp(),
          // What it moved from and to, so the log alone can be replayed
          // and checked without joining back to the item.
          quantityBefore,
          quantityAfter,
        });

        tx.update(itemRef, {
          quantityOnHand: quantityAfter,
          updatedBy: request.auth!.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      if (error instanceof MovementError) {
        throw new HttpsError("failed-precondition", error.message);
      }
      throw error;
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "inventory",
      action: "stock_moved",
      targetCollection: FirestorePaths.inventoryTransactions(schoolId),
      targetId: movementRef.id,
      newValue: {
        itemId,
        itemName,
        kind: MOVEMENT_LABELS[movement.kind],
        quantity: movement.quantity,
        issuedTo: movement.issuedTo,
        quantityBefore,
        quantityAfter,
      },
      success: true,
    });

    return {
      movementId: movementRef.id,
      itemName,
      quantityBefore,
      quantityAfter,
    };
  }
);
