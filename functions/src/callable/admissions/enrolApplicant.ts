import * as admin from "firebase-admin";
import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {requireCallerClaims, requireRole, requireSameSchool} from "../../shared/auth/claims";
import {writeAuditLog} from "../../shared/audit/writeAuditLog";
import {FirestorePaths} from "../../shared/firestore-paths";
import {getNextSequence} from "../../shared/counters/getNextSequence";
import {formatStudentNumber} from "../../shared/students/studentNumber";
import {isValidEducationLevel, usesProgramCatalogue} from "../../shared/education/educationLevel";

interface EnrolApplicantData {
  schoolId: string;
  applicantId: string;
  /** The class they are joining. Not on the applicant: it is decided now. */
  section: string;
  /** Required on a student record, and not asked for at enquiry. */
  birthDate: string;
}

const ADMISSIONS_ROLES = ["director", "admin", "registrar"];

/**
 * Turns an applicant into a student, exactly once.
 *
 * ## Why this is its own callable
 *
 * Enrolment is the only stage with a record behind it, so it cannot be a
 * stage somebody sets. An applicant marked "enrolled" with no student
 * record is a child the school believes is enrolled and the registrar
 * cannot find -- and the family finds out on the first day of classes.
 *
 * ## Why it cannot happen twice
 *
 * The applicant's `studentId` is written in the same transaction that
 * creates the student, and the transaction refuses when it is already
 * set. Two clicks on a slow connection, or a registrar coming back to a
 * screen they left open, produce one student and a clear message the
 * second time -- not twins.
 *
 * ## The reservation fee
 *
 * Whatever the family has already paid to hold the place is carried onto
 * the student record as a credit -- a negative balance, which this system
 * already treats as money the family is owed against what they will be
 * charged. A reservation fee that stayed on the applicant record would be
 * money the school has taken and the cashier cannot see, and the family
 * would be asked for it twice.
 */
export const enrolApplicant = onCall(
  {region: "asia-southeast1"},
  async (request: CallableRequest<EnrolApplicantData>) => {
    const callerClaims = requireCallerClaims(request);
    requireRole(callerClaims, ADMISSIONS_ROLES);

    const {schoolId, applicantId} = request.data;
    if (!schoolId || !applicantId) {
      throw new HttpsError("invalid-argument", "schoolId and applicantId are required.");
    }
    requireSameSchool(callerClaims, schoolId);

    const section = String(request.data.section ?? "").trim();
    if (!section) {
      throw new HttpsError(
        "invalid-argument",
        "Which class they are joining is required. A student with no section " +
          "is on no class list."
      );
    }

    const birthDate = request.data.birthDate ? new Date(request.data.birthDate) : null;
    if (!birthDate || Number.isNaN(birthDate.getTime())) {
      throw new HttpsError("invalid-argument", "A valid birthday is required to enrol.");
    }
    if (birthDate.getTime() > Date.now()) {
      throw new HttpsError("invalid-argument", "A birthday cannot be in the future.");
    }

    const db = admin.firestore();
    const applicantRef = db.doc(FirestorePaths.applicantDoc(schoolId, applicantId));
    const callerUid = request.auth!.uid;
    const callerName = (request.auth!.token.name as string) ?? "Unknown";

    // Read first, outside the transaction, for the checks that need
    // other documents -- a transaction may not read after it writes, and
    // the program lookup would otherwise have to happen inside it.
    const preview = await applicantRef.get();
    if (!preview.exists || preview.data()?.isDeleted === true) {
      throw new HttpsError("not-found", "That enquiry is not on file.");
    }
    const applicant = preview.data() ?? {};

    if (applicant.studentId) {
      throw new HttpsError(
        "already-exists",
        `${applicant.firstName ?? "This applicant"} has already been enrolled. ` +
          "Their student record is on the roster."
      );
    }
    if (applicant.stage !== "reserved" && applicant.stage !== "offered") {
      throw new HttpsError(
        "failed-precondition",
        "Only a family who has been offered a place can be enrolled. Move " +
          "them through the pipeline first."
      );
    }

    const educationLevel = String(applicant.educationLevel ?? "");
    if (!isValidEducationLevel(educationLevel)) {
      throw new HttpsError(
        "invalid-argument",
        "This enquiry has no valid division on it, so there is nothing to " +
          "enrol them into."
      );
    }

    // The same denormalisation registerStudent does, and for the same
    // reason: every downstream security rule scopes on the student
    // document alone, never a join onto programs at read time.
    let programName: string | null = null;
    let department: string | null = null;
    const programId = (applicant.programId as string | null) ?? null;
    if (usesProgramCatalogue(educationLevel)) {
      if (!programId) {
        throw new HttpsError(
          "invalid-argument",
          "A Senior High or College applicant needs a strand or program before " +
            "they can be enrolled."
        );
      }
      const programSnap = await db.doc(FirestorePaths.programDoc(schoolId, programId)).get();
      if (!programSnap.exists || programSnap.data()?.isDeleted) {
        throw new HttpsError("not-found", "That strand or program is not on file.");
      }
      if ((programSnap.data()?.educationLevel as string) !== educationLevel) {
        throw new HttpsError(
          "invalid-argument",
          "That strand or program belongs to a different division."
        );
      }
      programName = (programSnap.data()?.name as string) ?? null;
      department = (programSnap.data()?.department as string) ?? null;
    }

    // Drawn before the transaction, because getNextSequence runs one of
    // its own and they cannot nest. A transaction that then fails leaves
    // a gap in the student numbers -- visible, explicable, and far less
    // costly than the alternative, which is two children sharing one
    // number.
    const sequence = await getNextSequence(schoolId, "studentNumber");
    const studentNumber = formatStudentNumber(sequence, new Date().getFullYear());

    const reservationPaid = Number(applicant.reservationFeePaid ?? 0) || 0;

    const studentRef = db.collection(FirestorePaths.students(schoolId)).doc();

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(applicantRef);
      // Re-read inside the transaction. The check above is for a good
      // message; this one is the guarantee, and it is the one that holds
      // when two clicks arrive at once.
      if (snap.data()?.studentId) {
        throw new HttpsError(
          "already-exists",
          "That applicant was enrolled a moment ago. There is one student " +
            "record for them, not two."
        );
      }

      tx.create(studentRef, {
        id: studentRef.id,
        schoolId,
        userId: null,
        studentNumber,
        firstName: applicant.firstName ?? "",
        lastName: applicant.lastName ?? "",
        middleName: applicant.middleName ?? null,
        educationLevel,
        gradeLevel: applicant.gradeLevel ?? "",
        section,
        programId,
        programName,
        department,
        status: "enrolled",
        enrollmentDate: admin.firestore.FieldValue.serverTimestamp(),
        birthDate: admin.firestore.Timestamp.fromDate(birthDate),
        guardianContacts: applicant.guardianName ?
          [
            {
              name: applicant.guardianName,
              relationship: "Guardian",
              phone: applicant.guardianPhone ?? "",
              email: applicant.guardianEmail ?? null,
            },
          ] :
          [],
        // Negative is a credit in this system: money the family has
        // already handed over, against fees not yet assessed.
        balance: reservationPaid > 0 ? -reservationPaid : 0,
        photoUrl: null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: callerUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: callerUid,
        deletedAt: null,
        deletedBy: null,
        isDeleted: false,
      });

      tx.update(applicantRef, {
        stage: "enrolled",
        stageChangedAt: admin.firestore.FieldValue.serverTimestamp(),
        studentId: studentRef.id,
        lastUpdatedByName: callerName,
        updatedBy: callerUid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    await writeAuditLog({
      schoolId,
      userId: callerUid,
      userRole: callerClaims.role,
      userName: callerName,
      module: "admissions",
      action: "enrol",
      targetCollection: FirestorePaths.students(schoolId),
      targetId: studentRef.id,
      newValue: {
        applicantId,
        studentNumber,
        section,
        openingCredit: reservationPaid,
      },
      success: true,
    });

    return {studentId: studentRef.id, studentNumber, openingCredit: reservationPaid};
  }
);
