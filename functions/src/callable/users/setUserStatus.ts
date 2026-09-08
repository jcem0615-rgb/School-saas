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
// The Admin, who operates the school, and the Owner, who is the only one
// above them.
//
// The Director used to be here and is not any more: suspending an account
// hands somebody their access or takes it away, which is an operational
// act, and Director and Principal supervise rather than operate (see the
// note at the top of firestore.rules).
//
// That leaves a question this function has to answer rather than fall
// into. The guard below says a Director's or Principal's account cannot
// be suspended by an Admin -- a lower-privilege role must not be able to
// lock out the person supervising them, and that matters *more* now that
// the Director cannot suspend the Admin back. But with the Director gone
// from this list, "only a Director may" would mean nobody in the school
// could ever deactivate a Principal who left. So the Owner is here: they
// already create a school's Director, and they are who a school goes to
// for exactly this.
const STATUS_ALLOWED_ROLES = ["owner", "admin"];

export const setUserStatus = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetUserStatusData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, STATUS_ALLOWED_ROLES);

    const {schoolId, targetUserId, status} = request.data;
    if (!schoolId || !targetUserId || !["active", "suspended"].includes(status)) {
      throw new HttpsError("invalid-argument", "Missing or invalid arguments.");
    }
    // The Owner belongs to no school, so there is no school to match.
    if (callerClaims.role !== "owner") {
      requireSameSchool(callerClaims, schoolId);
    }

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

    // A Director's or Principal's account cannot be suspended by the
    // Admin: an operator must not be able to lock out the person
    // supervising them, and since the Director can no longer suspend the
    // Admin in return, this is the only thing holding that line. The
    // Owner can, which is where a school takes the request.
    if ((user.role === "director" || user.role === "principal") && callerClaims.role !== "owner") {
      throw new HttpsError(
        "permission-denied",
        "A Director's or Principal's account is changed by the Owner, not from inside the school."
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
