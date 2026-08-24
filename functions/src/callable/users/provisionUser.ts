import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {randomBytes} from "crypto";
import {setUserClaims, requireCallerClaims} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {isValidEducationLevel} from "../../shared/education/educationLevel";

interface EmployeeInfo {
  department: string;
  position: string;
  dateHired: string; // ISO date string
  /**
   * Optional data-isolation scope for Registrar/Faculty/Guidance staff.
   * Left unset (null/undefined), the staff member sees their role's
   * normal cross-division access -- this is what keeps every existing
   * school/test that never sets this working unchanged. Set it, and
   * firestore.rules actually enforces it: this staff member's access to
   * students/grades/payments/guidanceRecords/summons is restricted to
   * students in the same division (and, for College, optionally the
   * same department too).
   */
  assignedDivision?: string; // 'elementary' | 'high_school' | 'college'
  assignedDepartment?: string;
}

interface ProvisionUserData {
  schoolId: string;
  role: string;
  firstName: string;
  lastName: string;
  email: string;
  employeeInfo?: EmployeeInfo;
  /** For role === 'student': links this new portal account to an existing students/{id} academic record. */
  linkedStudentId?: string;
  /** For role === 'parent': the students/{id} academic record IDs this parent should see. */
  linkedStudentIds?: string[];
}

// Roles that are allowed to provision a new account, and which roles
// each of them is permitted to create. Kept explicit (not "any staff can
// create any role") so, e.g., a Registrar account can never mint itself
// a Director account even if the client were compromised.
const PROVISIONING_MATRIX: Record<string, string[]> = {
  // The Owner stands up a new school's leadership: a Director to run it
  // and an Admin to do the day-to-day setup, without having to sign in as
  // the Director first just to create the Admin.
  owner: ["director", "admin"],
  director: ["admin", "principal", "registrar", "faculty", "staff", "guidance"],
  admin: ["principal", "registrar", "faculty", "staff", "guidance"],
  registrar: ["student", "parent"],
};

// "owner" appears in no row of the matrix above, and this makes that
// explicit rather than incidental. There is exactly one Owner and it is
// established once, by bootstrapOwner, against a server-side email --
// never minted through the ordinary provisioning path. If a future edit
// adds "owner" to some row by accident, this still refuses.
const UNPROVISIONABLE_ROLES = ["owner"];

function generateTempPassword(): string {
  // 12 random bytes -> 16 char base64url-ish string, filtered to
  // alphanumerics and padded to guarantee it passes password validation.
  const raw = randomBytes(12).toString("base64").replace(/[^a-zA-Z0-9]/g, "");
  return (raw + "Aa1").slice(0, 14);
}

export const provisionUser = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<ProvisionUserData>) => {
    const callerClaims = requireCallerClaims(request);
    const {schoolId, role, firstName, lastName, email, employeeInfo, linkedStudentId, linkedStudentIds} =
      request.data;

    if (!schoolId || !role || !firstName || !lastName || !email) {
      throw new HttpsError("invalid-argument", "Missing required fields.");
    }

    if (UNPROVISIONABLE_ROLES.includes(role)) {
      throw new HttpsError(
        "permission-denied",
        `A ${role} account cannot be created this way.`
      );
    }

    const allowedTargetRoles = PROVISIONING_MATRIX[callerClaims.role];
    if (!allowedTargetRoles || !allowedTargetRoles.includes(role)) {
      throw new HttpsError(
        "permission-denied",
        `Your role (${callerClaims.role}) cannot create a ${role} account.`
      );
    }

    // Owner (platform-level) provisions across schools by design; every
    // other caller may only provision within their own tenant.
    if (callerClaims.role !== "owner" && callerClaims.schoolId !== schoolId) {
      throw new HttpsError("permission-denied", "You cannot provision users for another school.");
    }

    const db = admin.firestore();

    // Validate linking references BEFORE minting an Auth account -- a bad
    // reference should fail cleanly, not leave an orphaned account behind.
    let studentRecordRef: admin.firestore.DocumentReference | null = null;
    if (role === "student" && linkedStudentId) {
      studentRecordRef = db.doc(FirestorePaths.studentDoc(schoolId, linkedStudentId));
      const snap = await studentRecordRef.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "Linked student record not found.");
      }
      if (snap.data()?.userId) {
        throw new HttpsError("failed-precondition", "This student record already has a linked account.");
      }
    }
    if (role === "parent" && linkedStudentIds && linkedStudentIds.length > 0) {
      const checks = await Promise.all(
        linkedStudentIds.map((id) => db.doc(FirestorePaths.studentDoc(schoolId, id)).get())
      );
      const missing = checks.filter((snap) => !snap.exists);
      if (missing.length > 0) {
        throw new HttpsError("not-found", "One or more linked student records were not found.");
      }
    }

    if (
      employeeInfo?.assignedDivision !== undefined &&
      employeeInfo.assignedDivision !== null &&
      !isValidEducationLevel(employeeInfo.assignedDivision)
    ) {
      throw new HttpsError(
        "invalid-argument",
        "assignedDivision must be one of: elementary, high_school, college."
      );
    }

    const tempPassword = generateTempPassword();

    let authRecord;
    try {
      authRecord = await admin.auth().createUser({
        email,
        password: tempPassword,
        displayName: `${firstName} ${lastName}`,
      });
    } catch (err: unknown) {
      const code = (err as {code?: string}).code;
      if (code === "auth/email-already-exists") {
        throw new HttpsError("already-exists", "An account with this email already exists.");
      }
      throw new HttpsError("internal", "Failed to create the account. Please try again.");
    }

    await setUserClaims(authRecord.uid, {
      schoolId,
      role,
      status: "active",
      mustChangePassword: true,
    });

    const qrCode = randomBytes(16).toString("hex"); // opaque token, not the raw uid

    await db.doc(FirestorePaths.userDoc(schoolId, authRecord.uid)).set({
      id: authRecord.uid,
      schoolId,
      role,
      firstName,
      lastName,
      email,
      status: "active",
      mustChangePassword: true,
      qrCode,
      photoUrl: null,
      employeeInfo: employeeInfo ?? null,
      linkedStudentIds: role === "parent" ? (linkedStudentIds ?? []) : null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: request.auth!.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
      deletedAt: null,
      deletedBy: null,
      isDeleted: false,
    });

    if (studentRecordRef) {
      await studentRecordRef.update({
        userId: authRecord.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: request.auth!.uid,
      });
    }

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: request.auth!.token.name as string ?? "Unknown",
      module: "users",
      action: "create",
      targetCollection: FirestorePaths.users(schoolId),
      targetId: authRecord.uid,
      newValue: {role, firstName, lastName, email},
      success: true,
    });

    // In production this temp password is emailed via a transactional
    // email provider rather than returned to the caller; returned here
    // directly so the admin UI can display it once for manual hand-off,
    // matching how many PH school offices actually operate (front-desk
    // staff writes the temp credential on a slip of paper for the new hire).
    return {uid: authRecord.uid, tempPassword};
  }
);
