import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {formatStudentNumber} from "../../shared/students/studentNumber";
import {isValidEducationLevel} from "../../shared/education/educationLevel";

interface GuardianContact {
  name: string;
  relationship: string;
  phone: string;
  email?: string;
}

interface RegisterStudentData {
  schoolId: string;
  firstName: string;
  lastName: string;
  middleName?: string;
  educationLevel: string; // 'elementary' | 'high_school' | 'college'
  gradeLevel: string; // e.g. "Grade 7", "Grade 11", or "1st Year" for college
  section: string;
  programId?: string; // required when educationLevel === 'college'
  enrollmentDate?: string; // ISO date, defaults to now
  birthDate?: string; // ISO date; printed on the student's ID card
  guardianContacts?: GuardianContact[];
}

// Student Registration is a Registrar-primary responsibility; Director/
// Admin can also register in smaller schools where roles overlap.
const REGISTER_ALLOWED_ROLES = ["director", "admin", "registrar"];

export const registerStudent = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<RegisterStudentData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, REGISTER_ALLOWED_ROLES);

    const {
      schoolId,
      firstName,
      lastName,
      middleName,
      educationLevel,
      gradeLevel,
      section,
      programId,
      enrollmentDate,
      birthDate,
      guardianContacts,
    } = request.data;

    if (!schoolId || !firstName || !lastName || !gradeLevel || !section) {
      throw new HttpsError("invalid-argument", "Missing required student fields.");
    }
    if (!isValidEducationLevel(educationLevel)) {
      throw new HttpsError(
        "invalid-argument",
        "educationLevel must be one of: elementary, high_school, college."
      );
    }
    requireSameSchool(callerClaims, schoolId);

    const db = admin.firestore();

    // College students must be enrolled in a program that actually
    // exists; the program's department is denormalized onto the student
    // record here so every downstream security rule (grades, payments,
    // guidanceRecords, summons) can division/department-scope access
    // with a single get() on the student doc, never an extra join onto
    // programs at read time.
    let programName: string | null = null;
    let department: string | null = null;
    if (educationLevel === "college") {
      if (!programId) {
        throw new HttpsError("invalid-argument", "A college student must be enrolled in a program.");
      }
      const programSnap = await db.doc(FirestorePaths.programDoc(schoolId, programId)).get();
      if (!programSnap.exists || programSnap.data()?.isDeleted) {
        throw new HttpsError("not-found", "Selected program not found.");
      }
      programName = (programSnap.data()?.name as string) ?? null;
      department = (programSnap.data()?.department as string) ?? null;
    } else if (programId) {
      throw new HttpsError(
        "invalid-argument",
        "programId is only applicable to college students."
      );
    }

    const sequence = await getNextSequence(schoolId, "studentNumber");
    const studentNumber = formatStudentNumber(sequence, new Date().getFullYear());

    const studentRef = db.collection(FirestorePaths.students(schoolId)).doc();
    await studentRef.set({
      id: studentRef.id,
      schoolId,
      userId: null, // linked later if/when a portal account is provisioned
      studentNumber,
      firstName,
      lastName,
      middleName: middleName ?? null,
      educationLevel,
      gradeLevel,
      section,
      programId: programId ?? null,
      programName,
      department,
      status: "enrolled",
      enrollmentDate: admin.firestore.Timestamp.fromDate(
        enrollmentDate ? new Date(enrollmentDate) : new Date()
      ),
      // Optional: an ID card prints it, but a record with no birth date
      // on file is still a valid enrolment, so this never blocks
      // registration.
      birthDate: birthDate ? admin.firestore.Timestamp.fromDate(new Date(birthDate)) : null,
      guardianContacts: guardianContacts ?? [],
      balance: 0,
      photoUrl: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      createdBy: request.auth!.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: request.auth!.uid,
      deletedAt: null,
      deletedBy: null,
      isDeleted: false,
    });

    await writeAuditLog({
      schoolId,
      userId: request.auth!.uid,
      userRole: callerClaims.role,
      userName: (request.auth!.token.name as string) ?? "Unknown",
      module: "students",
      action: "register",
      targetCollection: FirestorePaths.students(schoolId),
      targetId: studentRef.id,
      newValue: {studentNumber, firstName, lastName, educationLevel, gradeLevel, section, programId},
      success: true,
    });

    return {studentId: studentRef.id, studentNumber};
  }
);
