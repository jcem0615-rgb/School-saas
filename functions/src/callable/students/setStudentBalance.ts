import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";

interface SetStudentBalanceData {
  schoolId: string;
  studentId: string;
  /** The assessed total the student owes, in PHP. */
  balance: number;
  /** Why it changed -- required, and written to the audit trail. */
  remarks: string;
}

// Assessing fees is a records/finance action, same list that may collect a
// payment. Faculty/Staff/Guidance have no business setting what a family
// owes.
const ALLOWED_ROLES = ["director", "admin", "registrar"];

/**
 * Sets a student's assessed balance.
 *
 * This exists because `balance` is deliberately not client-writable:
 * firestore.rules rejects any student update touching it, since the
 * payment transactions are otherwise its only writers and that is what
 * makes a balance trustworthy. But a registrar genuinely does need to set
 * the opening figure when fees are assessed, and to correct it when an
 * assessment changes.
 *
 * Routing that through a callable keeps both properties: the field stays
 * closed to direct client writes, and every change made here is attributed
 * and audited with a reason, rather than being an unexplained mutation.
 */
export const setStudentBalance = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<SetStudentBalanceData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ALLOWED_ROLES);

    const {schoolId, studentId, balance, remarks} = request.data;
    if (!schoolId || !studentId || typeof balance !== "number") {
      throw new HttpsError("invalid-argument", "Missing or invalid balance details.");
    }
    if (!Number.isFinite(balance)) {
      throw new HttpsError("invalid-argument", "Balance must be a real number.");
    }
    // A negative balance is legitimate -- it means the family is in credit,
    // usually after a refund or overpayment -- so only absurd values are
    // rejected, not negatives.
    if (Math.abs(balance) > 10_000_000) {
      throw new HttpsError("invalid-argument", "Balance is out of range.");
    }
    if (!remarks || !remarks.trim()) {
      throw new HttpsError("invalid-argument", "A reason is required when setting a balance.");
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();
    const studentRef = db.doc(FirestorePaths.studentDoc(schoolId, studentId));
    const snap = await studentRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Student record not found.");
    }
    const previousBalance = (snap.data()?.balance as number) ?? 0;

    await studentRef.update({
      balance,
      updatedBy: request.auth!.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "",
      module: "students",
      action: "update",
      targetCollection: FirestorePaths.students(schoolId),
      targetId: studentId,
      previousValue: {balance: previousBalance},
      newValue: {balance},
      success: true,
      remarks: remarks.trim(),
    });

    return {studentId, previousBalance, balance};
  }
);
