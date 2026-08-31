import {HttpsError} from "firebase-functions/v2/https";

/** One student's line in a rollover, as it arrives from a client. */
export interface PromotionDecisionData {
  studentId?: string;
  studentName?: string;
  recommended?: string;
  outcome?: string;
  fromGradeLevel?: string;
  fromSection?: string;
  toGradeLevel?: string;
  toSection?: string;
  generalAverage?: number | null;
  failedSubjects?: string[];
}

/** One student's line, validated and ready to store. */
export interface StoredPromotion {
  studentId: string;
  studentName: string;
  recommended: string;
  outcome: string;
  fromGradeLevel: string;
  fromSection: string;
  toGradeLevel: string;
  toSection: string;
  generalAverage: number | null;
  failedSubjects: string[];
  departsFromRecommendation: boolean;
}

export const PROMOTION_OUTCOMES = [
  "promoted",
  "conditional",
  "retained",
  "graduated",
  "held",
] as const;

/**
 * How many students one call may carry.
 *
 * A rollover is one write per student plus one promotion record, so a
 * page of 200 is 400 writes -- inside a batch's limit with room, and
 * small enough that a call that dies halfway has not left much behind.
 * The client pages; the per-student record id makes re-sending a page
 * harmless.
 */
export const MAX_DECISIONS_PER_CALL = 200;

/**
 * A school year, written the way schools write it: "2026-2027".
 *
 * Checked rather than accepted as free text because it is the document
 * id that stops a rollover running twice, and "2026-2027", "2026-27" and
 * "SY 2026-2027" are three different ids for one year.
 */
export function normaliseSchoolYear(raw: unknown): string {
  const text = String(raw ?? "").trim();
  const match = /^(\d{4})\s*[-/]\s*(\d{4})$/.exec(text);
  if (!match) {
    throw new HttpsError(
      "invalid-argument",
      `"${text}" is not a school year. Write it as 2026-2027.`
    );
  }
  const start = Number(match[1]);
  const end = Number(match[2]);
  if (end !== start + 1) {
    throw new HttpsError(
      "invalid-argument",
      `${text} spans ${end - start} years. A school year runs from one year ` +
        "to the next."
    );
  }
  return `${start}-${end}`;
}

/**
 * Validates the decisions in one page of a rollover.
 *
 * The client screen checks the same things. This checks them again
 * because the screen is not the only way to reach here, and because the
 * cost of a wrong row is a child in the wrong year for a school year --
 * found in June, by the child.
 *
 * What it will not do is second-guess the outcome. A registrar may
 * promote a student the marks say should be retained; that is their
 * decision to make and the record keeps both, so the departure is
 * visible afterwards rather than being silently prevented here.
 */
export function validateDecisions(raw: PromotionDecisionData[] | undefined): StoredPromotion[] {
  const decisions = raw ?? [];
  if (decisions.length === 0) {
    throw new HttpsError("invalid-argument", "There is nothing to roll over.");
  }
  if (decisions.length > MAX_DECISIONS_PER_CALL) {
    throw new HttpsError(
      "invalid-argument",
      `Too many students in one go (${decisions.length}). Send at most ` +
        `${MAX_DECISIONS_PER_CALL} at a time.`
    );
  }

  const seen = new Set<string>();
  const validated: StoredPromotion[] = [];

  for (const decision of decisions) {
    const studentId = String(decision.studentId ?? "").trim();
    if (!studentId) {
      throw new HttpsError("invalid-argument", "A decision arrived with no student on it.");
    }
    if (seen.has(studentId)) {
      // Two rows for one student is a client bug, and applying both
      // would move them twice.
      throw new HttpsError(
        "invalid-argument",
        `${decision.studentName || studentId} appears twice in this batch.`
      );
    }
    seen.add(studentId);

    const outcome = String(decision.outcome ?? "").trim();
    if (!(PROMOTION_OUTCOMES as readonly string[]).includes(outcome)) {
      throw new HttpsError(
        "invalid-argument",
        `"${outcome}" is not an outcome. It must be one of: ` +
          `${PROMOTION_OUTCOMES.join(", ")}.`
      );
    }

    const recommended = String(decision.recommended ?? "").trim();
    if (!(PROMOTION_OUTCOMES as readonly string[]).includes(recommended)) {
      throw new HttpsError(
        "invalid-argument",
        "Every decision has to carry the outcome that was recommended for " +
          "it, so a departure from it stays visible afterwards."
      );
    }

    const toGradeLevel = String(decision.toGradeLevel ?? "").trim();
    const toSection = String(decision.toSection ?? "").trim();

    // A promotion with nowhere to go is the failure this whole feature
    // has to avoid: the student's year would be blanked, and the class
    // lists in September would be missing a child nobody can find.
    if (outcome === "promoted" && (!toGradeLevel || !toSection)) {
      throw new HttpsError(
        "failed-precondition",
        `${decision.studentName || studentId} is being promoted but has no ` +
          "year and section to go to."
      );
    }

    const average = decision.generalAverage;
    if (average !== null && average !== undefined) {
      if (typeof average !== "number" || !Number.isFinite(average)) {
        throw new HttpsError("invalid-argument", "A general average has to be a number.");
      }
    }

    validated.push({
      studentId,
      studentName: String(decision.studentName ?? "").trim() || studentId,
      recommended,
      outcome,
      fromGradeLevel: String(decision.fromGradeLevel ?? "").trim(),
      fromSection: String(decision.fromSection ?? "").trim(),
      toGradeLevel,
      toSection,
      generalAverage: average === undefined ? null : average,
      failedSubjects: (decision.failedSubjects ?? [])
        .filter((s): s is string => typeof s === "string")
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
      departsFromRecommendation: outcome !== recommended,
    });
  }

  return validated;
}

/**
 * What a rollover does to the student record itself.
 *
 * Returned rather than written here so the shape is testable and so the
 * one place that decides "retained means change nothing" is not spread
 * across a callable. Null means leave the student alone.
 */
export function studentUpdateFor(decision: StoredPromotion): Record<string, unknown> | null {
  switch (decision.outcome) {
  case "promoted":
    return {
      gradeLevel: decision.toGradeLevel,
      section: decision.toSection,
    };
  case "graduated":
    // The record stays; the status changes. A graduate is not deleted --
    // they come back for a transcript years later, and the Form 137 has
    // to still be there.
    return {status: "graduated"};
  case "retained":
  case "conditional":
  case "held":
    // Deliberately nothing. A retained student stays in the year and
    // the section they are in, and a conditional one has not finished
    // the remedial classes yet -- writing anything here would be the
    // system deciding something the school has not.
    return null;
  default:
    return null;
  }
}
