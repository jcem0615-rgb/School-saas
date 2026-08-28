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
}

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

const norm = (value: string | null | undefined): string =>
  (value ?? "").trim().toLowerCase();

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
  return `${what} ${b.subject} with ${b.teacherName} in ${b.section}.`;
}

/** Minutes-from-midnight bounds a real class fits inside. */
export const MIN_CLASS_MINUTES = 5;
export const MAX_CLASS_MINUTES = 12 * 60;
