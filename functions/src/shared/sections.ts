/**
 * What counts as the same class.
 *
 * A section name is typed by hand in several places -- the student
 * record, the teacher's assignment, the timetable -- and "Grade 10 -
 * Rizal", "Grade 10 - rizal" and "Grade 10  -  Rizal " are the same
 * class to everybody in the building. Comparing them as raw strings
 * fails silently and in the worst direction: a parent simply never gets
 * the notice about tomorrow's field trip, and nothing anywhere says why.
 *
 * Messaging already had this, and used it to decide whether a parent
 * could reach their child's teacher at all. Announcements did not, and
 * matched section names exactly. One copy now, in a place neither module
 * owns, for the same reason `schoolClock` is one copy: two
 * implementations of "is this the same class" is the shape that drifts.
 */
export function normalizeSection(section: string | null | undefined): string {
  return (section ?? "").trim().toLowerCase().replace(/\s+/g, " ");
}

/** The same normalisation over a list, with blanks dropped. */
export function normalizeSections(sections: Iterable<string>): Set<string> {
  const out = new Set<string>();
  for (const section of sections) {
    const key = normalizeSection(section);
    if (key) out.add(key);
  }
  return out;
}
