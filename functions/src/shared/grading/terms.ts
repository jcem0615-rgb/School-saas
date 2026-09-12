/**
 * The four quarters a Philippine school year is graded in.
 *
 * The mirror of `app/lib/core/constants/school_terms.dart`, and it has to
 * stay one: the app decides what a teacher can file a mark under, and
 * this decides what the repair reads as the same thing.
 */
export const SCHOOL_TERMS = [
  "1st Quarter",
  "2nd Quarter",
  "3rd Quarter",
  "4th Quarter",
] as const;

const SHORTHANDS: Record<string, number> = {
  "1": 0, "q1": 0, "1st": 0, "first": 0, "first quarter": 0, "quarter 1": 0,
  "2": 1, "q2": 1, "2nd": 1, "second": 1, "second quarter": 1, "quarter 2": 1,
  "3": 2, "q3": 2, "3rd": 2, "third": 2, "third quarter": 2, "quarter 3": 2,
  "4": 3, "q4": 3, "4th": 3, "fourth": 3, "fourth quarter": 3, "quarter 4": 3,
};

/**
 * Maps the shorthands people type onto the canonical quarter names.
 *
 * Anything unrecognised comes back untouched. A school running its own
 * term names keeps them -- rewriting "Prelim" to a quarter would be this
 * software deciding how a school divides its year.
 */
export function canonicalTerm(raw: string): string {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return trimmed;
  const exact = SCHOOL_TERMS.find(
    (term) => term.toLowerCase() === trimmed.toLowerCase()
  );
  if (exact) return exact;
  const index = SHORTHANDS[trimmed.toLowerCase()];
  return index === undefined ? trimmed : SCHOOL_TERMS[index];
}
