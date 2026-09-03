import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {formatStudentNumber} from "../../shared/students/studentNumber";
import {isValidEducationLevel, usesProgramCatalogue} from "../../shared/education/educationLevel";
import {validateContactDetails, ContactDetailsError} from "../../shared/students/contactDetails";

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
  birthDate?: string; // ISO date; required to register, printed on the ID card
  /** The student's own address. Becomes their sign-in when a portal account is provisioned. */
  email?: string;
  /** The student's own mobile. What resetPasswordByPhone matches against. */
  phone?: string;
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
      email,
      phone,
      guardianContacts,
    } = request.data;

    if (!schoolId || !firstName || !lastName || !gradeLevel || !section) {
      throw new HttpsError("invalid-argument", "Missing required student fields.");
    }
    // Required to register, but the field stays nullable on the document:
    // records written before this rule existed have no birth date and must
    // remain readable and editable.
    const parsedBirthDate = birthDate ? new Date(birthDate) : null;
    if (!parsedBirthDate || Number.isNaN(parsedBirthDate.getTime())) {
      throw new HttpsError("invalid-argument", "A valid birthday is required.");
    }
    if (parsedBirthDate.getTime() > Date.now()) {
      throw new HttpsError("invalid-argument", "A birthday cannot be in the future.");
    }
    // Both optional -- a Grade 1 pupil has neither -- but a value that IS
    // given has to be usable, because the email becomes the account the
    // student signs in with and the number is what recovers it. The only
    // cheap moment to catch a typo is now; after this it is found by a
    // family who cannot get in, on the day they need to.
    let contact;
    try {
      contact = validateContactDetails({email, phone});
    } catch (err) {
      if (err instanceof ContactDetailsError) {
        throw new HttpsError("invalid-argument", err.message);
      }
      throw err;
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
    if (usesProgramCatalogue(educationLevel)) {
      if (!programId) {
        throw new HttpsError(
          "invalid-argument",
          "A Senior High or College student must be enrolled in a strand or program."
        );
      }
      const programSnap = await db.doc(FirestorePaths.programDoc(schoolId, programId)).get();
      if (!programSnap.exists || programSnap.data()?.isDeleted) {
        throw new HttpsError("not-found", "Selected strand or program not found.");
      }
      // A college program is not a valid enrolment for a Senior High
      // student and vice versa. The client filters the dropdown by
      // division; this is the check that actually holds, since the
      // client's filtering is a convenience, not a boundary.
      const programLevel = (programSnap.data()?.educationLevel as string) ?? "college";
      if (programLevel !== educationLevel) {
        throw new HttpsError(
          "invalid-argument",
          "That strand or program belongs to a different division."
        );
      }
      programName = (programSnap.data()?.name as string) ?? null;
      department = (programSnap.data()?.department as string) ?? null;
    } else if (programId) {
      throw new HttpsError(
        "invalid-argument",
        "programId only applies to Senior High and College students."
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
      birthDate: admin.firestore.Timestamp.fromDate(parsedBirthDate),
      email: contact.email,
      phone: contact.phone,
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
