import {HttpsError} from "firebase-functions/v2/https";

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
 * applicant nobody can contact is not a lead, it is a row.
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
    guardianEmail: String(data.guardianEmail ?? "").trim() || null,
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
