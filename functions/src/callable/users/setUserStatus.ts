import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface SetUserStatusData {
  schoolId: string;
  targetUserId: string;
  status: "active" | "suspended";
}

// Since this build provisions accounts (via provisionUser) rather than
// accepting self-registration, there is no incoming queue of unverified
// signups to "approve." The equivalent control -- and what the Admin
// Portal's "User Approval" screen actually exercises -- is the ability to
// activate or suspend an existing account. A suspended user's custom claim
// flips to 'suspended', which is checked by isAccountActive() in
// firestore.rules and blocks their self-service profile edits immediately.
//
// Principal is deliberately NOT in this list yet -- account-security
// actions (suspend/activate, password reset) stay with Director/Admin for
// now even though Principal can manage division-level academic operations
// (see docs/16-principal-role.md). Easy to extend later if a school wants
// Principals to self-serve this for their own division's staff.
const STATUS_ALLOWED_ROLES = ["director", "admin"];

export const setUserStatus = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetUserStatusData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, STATUS_ALLOWED_ROLES);

    const {schoolId, targetUserId, status} = request.data;
    if (!schoolId || !targetUserId || !["active", "suspended"].includes(status)) {
      throw new HttpsError("invalid-argument", "Missing or invalid arguments.");
    }
    requireSameSchool(callerClaims, schoolId);

    if (targetUserId === request.auth!.uid) {
      throw new HttpsError("failed-precondition", "You cannot change your own account status.");
    }

    const db = admin.firestore();
    const userRef = db.doc(FirestorePaths.userDoc(schoolId, targetUserId));
    const snap = await userRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "User not found.");
    }
    const user = snap.data()!;

    // A Director's or Principal's account cannot be suspended by an
    // Admin -- prevents a lower-privilege role from locking out a higher
    // one. (Principal outranks Admin in academic authority even though,
    // for now, Principal itself cannot call this function at all --
    // see STATUS_ALLOWED_ROLES above.)
    if ((user.role === "director" || user.role === "principal") && callerClaims.role !== "director") {
      throw new HttpsError(
        "permission-denied",
        "Only a Director can change a Director's or Principal's status."
      );
    }

    await admin.auth().setCustomUserClaims(targetUserId, {
      schoolId,
      role: user.role,
      status,
      mustChangePassword: user.mustChangePassword ?? false,
    });

    await userRef.update({
      status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "users",
      action: status === "active" ? "user_activated" : "user_suspended",
      targetCollection: FirestorePaths.users(schoolId),
      targetId: targetUserId,
      previousValue: {status: user.status},
      newValue: {status},
      success: true,
    });

    return {success: true};
  }
);
