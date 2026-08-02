/**
 * The three-way split every school in this system is organized around,
 * per the business requirement: a single tenant (school) can run
 * Elementary, High School, and College under one roof (very common for
 * PH private schools), and every student record must declare which one
 * they belong to -- this is what the division-isolation rules in
 * firestore.rules key off of.
 */
export const EDUCATION_LEVELS = [
  "elementary",
  "high_school",
  "senior_high",
  "college",
] as const;

/**
 * The divisions whose students enrol in something from the `programs`
 * catalogue -- a strand for Senior High, a degree program for College.
 * Elementary and Junior High have neither, so a programId on one of
 * those records is a mistake rather than extra information.
 */
export const PROGRAM_LEVELS: readonly string[] = ["senior_high", "college"];

export function usesProgramCatalogue(level: string): boolean {
  return PROGRAM_LEVELS.includes(level);
}
export type EducationLevel = (typeof EDUCATION_LEVELS)[number];

export function isValidEducationLevel(value: unknown): value is EducationLevel {
  return typeof value === "string" && (EDUCATION_LEVELS as readonly string[]).includes(value);
}
