/**
 * A piece of work a class was given, and the marks against it.
 *
 * This is the thing the grading module did not have, and its absence was
 * the module's worst defect: `submitGrade` wrote a **new document every
 * time**, so a mark could be posted but never corrected. A teacher who
 * typed 80 out of 10 and re-entered 8 out of 10 ended the quarter with
 * 88 out of 20, because `computeQuarterlyGrade` sums the scores and the
 * maximums inside a component. The import knew: its own comment says "a
 * mark is posted, never replaced", and it works around it by refusing a
 * row identical to one already on file -- which catches a file run twice
 * and does nothing at all about a correction, since a corrected mark is
 * by definition not identical.
 *
 * Giving the work an identity fixes it by construction. One assessment
 * is one column in the class record; one student's mark against it is
 * one document, at a derived id, so entering it again replaces it.
 */

export const GRADING_COMPONENTS = [
  "written_work",
  "performance_task",
  "quarterly_assessment",
] as const;

export type GradingComponent = (typeof GRADING_COMPONENTS)[number];

export const COMPONENT_LABELS: Record<GradingComponent, string> = {
  written_work: "Written Work",
  performance_task: "Performance Tasks",
  quarterly_assessment: "Quarterly Assessment",
};

export function isGradingComponent(value: unknown): value is GradingComponent {
  return (GRADING_COMPONENTS as readonly string[]).includes(String(value));
}

export class GradingError extends Error {}

/** Two decimal places, half away from zero. */
export function round2(value: number): number {
  const scaled = value * 100;
  const rounded = scaled < 0 ? -Math.round(-scaled) : Math.round(scaled);
  return rounded / 100 + 0;
}

function text(raw: unknown, field: string, max = 120): string {
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new GradingError(`${field} is required.`);
  }
  const value = raw.trim();
  if (value.length > max) {
    throw new GradingError(`${field} is too long.`);
  }
  return value;
}

/**
 * A document id that is stable for the same class, and safe as a path.
 *
 * Subjects and sections are free text a school types -- "Grade 10 -
 * Rizal", "Mathematics 7" -- so they cannot go into an id unescaped.
 * Lower-cased and reduced to a narrow alphabet so "Mathematics" and
 * "mathematics " land on the same record rather than quietly becoming
 * two class records with two sets of weights.
 */
export function classKey(subject: string, section: string, term?: string): string {
  const part = (value: string) =>
    value
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "none";
  const parts = [part(subject), part(section)];
  if (term !== undefined) parts.push(part(term));
  return parts.join("__");
}

export interface ValidatedAssessment {
  subject: string;
  section: string;
  term: string;
  title: string;
  component: GradingComponent;
  maxScore: number;
}

/**
 * What a class assessment must say before it can be marked.
 *
 * `Number.isFinite` before the comparison, the same reason as everywhere
 * else in this codebase: `NaN <= 0` is false, `double.tryParse('NaN')`
 * returns NaN for one word typed into a box, and a NaN maximum makes
 * every percentage in the component NaN from then on.
 */
export function validateAssessment(input: {
  subject: unknown;
  section: unknown;
  term: unknown;
  title: unknown;
  component: unknown;
  maxScore: unknown;
}): ValidatedAssessment {
  if (!isGradingComponent(input.component)) {
    throw new GradingError(
      "Say which component this counts towards: written work, a performance " +
        "task, or the quarterly assessment."
    );
  }
  const maxScore = typeof input.maxScore === "number" ? input.maxScore : NaN;
  if (!Number.isFinite(maxScore)) {
    throw new GradingError("The total this is marked out of has to be a number.");
  }
  if (maxScore <= 0) {
    throw new GradingError("The total this is marked out of has to be more than zero.");
  }

  return {
    subject: text(input.subject, "Subject"),
    section: text(input.section, "Section"),
    term: text(input.term, "Term", 20),
    title: text(input.title, "A name for this piece of work"),
    component: input.component,
    maxScore: round2(maxScore),
  };
}

/**
 * One mark. Null is a deliberate blank -- the student has not sat it --
 * and is different from a zero, which is a mark of nothing.
 *
 * The distinction matters to the arithmetic: a blank leaves the piece of
 * work out of both the score and the total, and a zero counts the total
 * against the student. Collapsing them would mark a child absent from a
 * quiz as having failed it.
 */
export function validateScore(raw: unknown, maxScore: number): number | null {
  if (raw === null || raw === undefined || raw === "") return null;
  const score = typeof raw === "number" ? raw : Number(String(raw).trim());
  if (!Number.isFinite(score)) {
    throw new GradingError("A score has to be a number.");
  }
  if (score < 0) {
    throw new GradingError("A score cannot be negative.");
  }
  if (score > maxScore) {
    // Almost always the two columns filled in the wrong order, and a
    // mark over its own total goes into the component percentage as if
    // it were real. A school that genuinely gives bonus marks raises the
    // total the work is out of, which is the same arithmetic said
    // honestly.
    throw new GradingError(
      `A score of ${score} is higher than the ${maxScore} this is marked out of.`
    );
  }
  return round2(score);
}

/** The id of one student's mark against one assessment. */
export function scoreDocId(assessmentId: string, studentId: string): string {
  return `${assessmentId}_${studentId}`;
}
