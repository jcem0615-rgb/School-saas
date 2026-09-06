import {HttpsError} from "firebase-functions/v2/https";
import {normalizeEmail} from "../students/contactDetails";
import {normalizePhone} from "../auth/phone";

export const ADMISSION_STAGES = [
  "inquiry",
  "applied",
  "exam_scheduled",
  "exam_taken",
  "offered",
  "reserved",
  "enrolled",
  "declined",
  "withdrawn",
] as const;

export type AdmissionStage = (typeof ADMISSION_STAGES)[number];

/** The stages a school moves a family forward through, in order. */
const PIPELINE: AdmissionStage[] = [
  "inquiry",
  "applied",
  "exam_scheduled",
  "exam_taken",
  "offered",
  "reserved",
  "enrolled",
];

const CLOSED: AdmissionStage[] = ["enrolled", "declined", "withdrawn"];

export function isAdmissionStage(value: unknown): value is AdmissionStage {
  return (ADMISSION_STAGES as readonly string[]).includes(String(value));
}

/**
 * Which stages an applicant may be moved to from where they are.
 *
 * The same rule as the client's, checked again here because the screen
 * is not the only way in. A pipeline whose stages can be set freely
 * stops meaning anything within a term: somebody marks a family as
 * offered because that is the outcome they expect, and the funnel then
 * reports offers the school never made.
 */
export function nextStagesFrom(current: AdmissionStage): AdmissionStage[] {
  if (current === "enrolled") {
    // There is a student record behind it. Moving out would leave a
    // child enrolled in the school and an applicant record saying they
    // withdrew.
    return [];
  }
  if (CLOSED.includes(current)) {
    return ["inquiry"];
  }
  const at = PIPELINE.indexOf(current);
  const allowed: AdmissionStage[] = [];
  if (at >= 0 && at + 1 < PIPELINE.length) allowed.push(PIPELINE[at + 1]);
  if (at > 0) allowed.push(PIPELINE[at - 1]);
  allowed.push("declined", "withdrawn");
  return allowed;
}

/**
 * Refuses a move the pipeline does not allow, in words that say what to
 * do instead.
 *
 * Enrolment is deliberately not reachable this way at all: it is the one
 * stage with a student record behind it, and it is reached only by
 * `enrolApplicant`, which creates that record in the same breath. A
 * stage set to "enrolled" on its own would be an applicant the school
 * believes is a student and the registrar cannot find.
 */
export function requireLegalTransition(
  from: AdmissionStage,
  to: AdmissionStage
): void {
  if (from === to) {
    throw new HttpsError("failed-precondition", "That is already where they are.");
  }
  if (to === "enrolled") {
    throw new HttpsError(
      "failed-precondition",
      "Enrolling an applicant creates their student record, so it is done " +
        "by enrolling them rather than by setting the stage."
    );
  }
  const allowed = nextStagesFrom(from);
  if (allowed.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "An enrolled applicant has a student record behind them and cannot be " +
        "moved back out of it."
    );
  }
  if (!allowed.includes(to)) {
    throw new HttpsError(
      "failed-precondition",
      `An applicant at "${from}" can only move to: ${allowed.join(", ")}.`
    );
  }
}

/** One applicant's details, as they arrive from a client. */
export interface ApplicantData {
  firstName?: string;
  lastName?: string;
  middleName?: string;
  educationLevel?: string;
  gradeLevel?: string;
  programId?: string;
  programName?: string;
  guardianName?: string;
  guardianPhone?: string;
  guardianEmail?: string;
  /**
   * The applicant's own address and number.
   *
   * Both optional, because a Grade 1 applicant has neither. A Senior High
   * or College applicant has both, and they are the person the school
   * will actually be talking to -- and at enrolment these become the
   * student record's own contact details, which is the only route by
   * which a student who arrived through admissions can ever be given a
   * portal account or recover it by phone.
   */
  email?: string;
  phone?: string;
  source?: string;
  notes?: string;
}

/**
 * Validates the details of an enquiry.
 *
 * Thin on purpose. An enquiry is a phone call that somebody is typing up
 * while the caller is still on the line, and a form that refuses to save
 * without a middle name is a form that gets abandoned -- and then the
 * enquiry is a note on paper again, which is the thing this module
 * exists to stop.
 *
 * What it does insist on is a name and a way to ring them back. An
 * applicant nobody can contact is not a lead, it is a row -- and a number
 * that is not a number is the same row wearing a disguise, which is why
 * the guardian's phone is checked against the same matcher the rest of
 * the system uses rather than merely checked for being non-empty.
 */
export function validateApplicant(data: ApplicantData): Record<string, unknown> {
  const firstName = String(data.firstName ?? "").trim();
  const lastName = String(data.lastName ?? "").trim();
  if (!firstName || !lastName) {
    throw new HttpsError("invalid-argument", "The applicant's name is required.");
  }

  const guardianName = String(data.guardianName ?? "").trim();
  const guardianPhone = String(data.guardianPhone ?? "").trim();
  if (!guardianName || !guardianPhone) {
    throw new HttpsError(
      "invalid-argument",
      "A parent or guardian and a number to ring them on are required. An " +
        "applicant nobody can contact is not a lead."
    );
  }
  // Required AND usable. "0" satisfies non-empty and rings nobody, and
  // the whole justification for making this field mandatory is that
  // somebody can be rung back -- so the check has to mean it.
  if (!normalizePhone(guardianPhone)) {
    throw new HttpsError(
      "invalid-argument",
      `"${guardianPhone}" is not a mobile number this system can read. Use ` +
        "09171234567, +639171234567, or 9171234567."
    );
  }

  // Optional, and checked when given. This one goes further than the
  // record: at enrolment it is copied onto the student as a guardian
  // contact, so an address accepted here is an address the student form
  // and the student import would both have refused.
  const rawGuardianEmail = String(data.guardianEmail ?? "").trim();
  const guardianEmail = rawGuardianEmail ? normalizeEmail(rawGuardianEmail) : null;
  if (rawGuardianEmail && !guardianEmail) {
    throw new HttpsError(
      "invalid-argument",
      `"${rawGuardianEmail}" is not a valid email address for the guardian.`
    );
  }

  // The applicant's own. Becomes the student's at enrolment, and the
  // student's email is what a portal account gets created against.
  const rawEmail = String(data.email ?? "").trim();
  const email = rawEmail ? normalizeEmail(rawEmail) : null;
  if (rawEmail && !email) {
    throw new HttpsError(
      "invalid-argument",
      `"${rawEmail}" is not a valid email address for the applicant. This ` +
        "becomes their sign-in if they enrol."
    );
  }

  const phone = String(data.phone ?? "").trim();
  if (phone && !normalizePhone(phone)) {
    throw new HttpsError(
      "invalid-argument",
      `"${phone}" is not a mobile number this system can read. Use ` +
        "09171234567, +639171234567, or 9171234567."
    );
  }

  const gradeLevel = String(data.gradeLevel ?? "").trim();
  if (!gradeLevel) {
    throw new HttpsError(
      "invalid-argument",
      "Which year they are applying into is required."
    );
  }

  return {
    firstName,
    lastName,
    middleName: String(data.middleName ?? "").trim() || null,
    educationLevel: String(data.educationLevel ?? "").trim(),
    gradeLevel,
    programId: String(data.programId ?? "").trim() || null,
    programName: String(data.programName ?? "").trim() || null,
    guardianName,
    guardianPhone,
    guardianEmail,
    email,
    // Kept as typed, not normalised: "+63 917 555 0100" is what the
    // office reads back to a family. What is checked is that the matcher
    // can read it, so the stored form and the matched form agree.
    phone: phone || null,
    source: String(data.source ?? "").trim() || null,
    notes: String(data.notes ?? "").trim() || null,
  };
}

/**
 * Checks an entrance exam result.
 *
 * A score above the maximum is almost always the two fields filled in
 * the wrong order, and it would rank a child above everybody who sat the
 * same paper.
 */
export function validateExamResult(
  score: unknown,
  maxScore: unknown
): {score: number; maxScore: number} {
  const parsedScore = Number(score);
  const parsedMax = Number(maxScore);

  if (!Number.isFinite(parsedScore) || parsedScore < 0) {
    throw new HttpsError("invalid-argument", "That entrance exam score is not a number.");
  }
  if (!Number.isFinite(parsedMax) || parsedMax <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "What the entrance exam was out of is required, and has to be more than zero."
    );
  }
  if (parsedScore > parsedMax) {
    throw new HttpsError(
      "invalid-argument",
      `A score of ${parsedScore} is higher than the ${parsedMax} the paper ` +
        "was out of. Check the two fields are the right way round."
    );
  }
  return {score: parsedScore, maxScore: parsedMax};
}

/** Checks a reservation payment. */
export function validateReservationFee(amount: unknown): number {
  const parsed = Number(amount);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "A reservation fee has to be an amount above zero."
    );
  }
  return Math.round(parsed * 100) / 100;
}
