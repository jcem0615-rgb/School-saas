/**
 * Timetable clash arithmetic, free of Firestore types so it can be
 * tested on its own.
 *
 * The client checks all of this too, so an admin laying out a week is
 * told about a clash before the round trip. This is the copy that
 * matters: a callable is reachable without going through that screen,
 * and a timetable whose only guarantee lives in the UI has no guarantee.
 */

export interface TimetableBlock {
  id?: string;
  subject: string;
  section: string;
  teacherId: string;
  teacherName: string;
  room?: string | null;
  dayOfWeek: number;
  startMinute: number;
  endMinute: number;
  schoolYear: string;

  /**
   * Semester or quarter, for a school whose timetable changes partway
   * through the year. Null means it runs all year.
   */
  term?: string | null;
}

const norm = (value: string | null | undefined): string =>
  (value ?? "").trim().toLowerCase();

export type ClashKind = "teacher" | "section" | "room";

export interface Clash {
  kind: ClashKind;
  against: TimetableBlock;
}

/**
 * Touching ends do not overlap. A class ending at 9:00 and the next
 * starting at 9:00 is how every timetable in the country is written, and
 * calling that a clash would make the feature unusable on day one.
 */
export function overlaps(a: TimetableBlock, b: TimetableBlock): boolean {
  return (
    a.dayOfWeek === b.dayOfWeek &&
    a.startMinute < b.endMinute &&
    b.startMinute < a.endMinute
  );
}

/**
 * Whether two blocks are ever in the same week as each other.
 *
 * `term` carried the note "for schools whose timetable changes partway
 * through the year", and nothing read it. Two blocks in different
 * semesters never coexist, so calling them a clash made the second
 * semester impossible to enter: every block collided with its own
 * counterpart from the first. Senior High runs two semesters and a
 * college division runs two more, so that was not an edge case for the
 * schools this is built for -- it was the ordinary case.
 *
 * A block with no term runs all year and therefore shares the week with
 * every term, which is why a null on either side coexists with anything.
 */
export function sharesTerm(a: TimetableBlock, b: TimetableBlock): boolean {
  const left = norm(a.term);
  const right = norm(b.term);
  if (left === "" || right === "") return true;
  return left === right;
}

/** Every way `candidate` collides with what is already timetabled. */
export function findClashes(
  candidate: TimetableBlock,
  existing: TimetableBlock[]
): Clash[] {
  const clashes: Clash[] = [];
  const room = norm(candidate.room);

  for (const other of existing) {
    if (other.id && candidate.id && other.id === candidate.id) continue;
    if (other.schoolYear !== candidate.schoolYear) continue;
    if (!sharesTerm(candidate, other)) continue;
    if (!overlaps(candidate, other)) continue;

    if (other.teacherId === candidate.teacherId) {
      clashes.push({kind: "teacher", against: other});
    }
    if (norm(other.section) === norm(candidate.section)) {
      clashes.push({kind: "section", against: other});
    }
    // A blank room is not a room. Two blocks with no room recorded are
    // in no recorded place, not in the same one -- reporting that as a
    // clash would punish every school that does not timetable rooms.
    if (room && room === norm(other.room)) {
      clashes.push({kind: "room", against: other});
    }
  }
  return clashes;
}

export function describeClash(clash: Clash): string {
  const b = clash.against;
  const what =
    clash.kind === "teacher" ?
      "This teacher is already teaching then." :
      clash.kind === "section" ?
        "This section already has a class then." :
        "That room is already taken then.";
  const when = norm(b.term) === "" ? "" : ` (${b.term})`;
  return `${what} ${b.subject} with ${b.teacherName} in ${b.section}${when}.`;
}

/** Minutes-from-midnight bounds a real class fits inside. */
export const MIN_CLASS_MINUTES = 5;
export const MAX_CLASS_MINUTES = 12 * 60;
