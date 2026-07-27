/** Formats a sequential number into a human-readable student number, e.g. S-2026-000123. */
export function formatStudentNumber(sequence: number, year: number): string {
  return `S-${year}-${String(sequence).padStart(6, "0")}`;
}
