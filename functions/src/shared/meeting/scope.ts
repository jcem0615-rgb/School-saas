/**
 * Which lesson a person belongs in, checked again at the door.
 *
 * ## What this is defending against
 *
 * Getting into a video class already takes three things: an account in
 * this school, a line in this lesson's register, and the passcode the
 * teacher read out. This is the fourth, and it exists because the first
 * three can all be true of somebody who has since moved.
 *
 * A register is built when the lesson opens and stays as it was. A
 * student record does not: children are promoted a grade, moved between
 * sections mid-year, transferred between departments, switched from one
 * strand to another, withdrawn. Every one of those leaves an old mark
 * pointing at a lesson the child is no longer part of -- in a different
 * section, a different grade, sometimes a different department of the
 * same school.
 *
 * So the lesson records the scope it was opened for, and the door
 * compares the person standing in it against that scope as they are
 * *now*, not as they were when the roll was taken.
 *
 * ## Why the scope is a set and not a value
 *
 * Today a roll is built from one section, so every set has one member.
 * An elective, a college course, a remedial group pulled from three
 * sections -- all of them are one lesson with several sections in it,
 * and a scope that could only hold one value would have to be widened
 * or abandoned the first time a school ran one. A set costs nothing now
 * and does not have to be revisited then.
 *
 * ## Why an unrecorded scope is not a refusal
 *
 * Sessions opened before this existed carry no scope, and students
 * enrolled before a field existed carry no value for it. Refusing those
 * would lock schools out of their own lessons to enforce a rule about
 * records that have not moved. So a dimension is checked when the
 * lesson names it and the person has a value for it, and the section --
 * which every lesson and every student has always had -- is checked
 * always.
 */

/** What a lesson was opened for. Arrays, sorted, possibly empty. */
export interface LessonScope {
  section?: string[];
  gradeLevel?: string[];
  department?: string[];
  educationLevel?: string[];
  programId?: string[];
}

/** One person's record, as it stands now. */
export interface LearnerScope {
  schoolId?: unknown;
  status?: unknown;
  section?: unknown;
  gradeLevel?: unknown;
  department?: unknown;
  educationLevel?: unknown;
  programId?: unknown;
}

/** The dimensions, in the order a person would think of them. */
const DIMENSIONS: {
  key: keyof LessonScope;
  noun: string;
  /** Checked even when the person's record is silent about it. */
  always: boolean;
}[] = [
  {key: "section", noun: "section", always: true},
  {key: "gradeLevel", noun: "grade level", always: false},
  {key: "educationLevel", noun: "education level", always: false},
  {key: "department", noun: "department", always: false},
  {key: "programId", noun: "programme", always: false},
];

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** The scope of a roll, read off the records it was built from. */
export function scopeOfRoll(students: LearnerScope[]): LessonScope {
  const scope: LessonScope = {};
  for (const {key} of DIMENSIONS) {
    const values = new Set<string>();
    for (const student of students) {
      const value = text(student[key as keyof LearnerScope]);
      if (value) values.add(value);
    }
    if (values.size > 0) scope[key] = [...values].sort();
  }
  return scope;
}

/** Reads a scope off a stored session document, ignoring anything odd. */
export function scopeFrom(stored: unknown): LessonScope {
  const scope: LessonScope = {};
  if (typeof stored !== "object" || stored === null) return scope;
  const source = stored as Record<string, unknown>;
  for (const {key} of DIMENSIONS) {
    const value = source[key];
    if (!Array.isArray(value)) continue;
    const values = value.map(text).filter((one) => one.length > 0);
    if (values.length > 0) scope[key] = [...new Set(values)].sort();
  }
  return scope;
}

/**
 * Why this person may not join this lesson, or null if they may.
 *
 * A sentence rather than a code, because it is shown to whoever is
 * holding the phone -- and "You are not in that class" told a teacher
 * nothing when a child had been moved to another section that morning.
 */
export function scopeRefusal(
  lesson: LessonScope,
  learner: LearnerScope,
  options: {schoolId: string}
): string | null {
  if (text(learner.schoolId) !== options.schoolId) {
    // Should be unreachable -- the caller's claims are checked first --
    // and checked anyway, because this is the boundary that matters
    // most and the cheapest place to be sure of it.
    return "That class belongs to another school.";
  }

  const status = text(learner.status);
  if (status && status !== "enrolled") {
    return "That account is no longer enrolled, so it cannot join a class.";
  }

  for (const {key, noun, always} of DIMENSIONS) {
    const allowed = lesson[key];
    if (!allowed || allowed.length === 0) continue;
    const mine = text(learner[key as keyof LearnerScope]);
    if (!mine) {
      if (!always) continue;
      return `That class is for another ${noun}.`;
    }
    if (!allowed.includes(mine)) {
      return `That class is for another ${noun}.`;
    }
  }

  return null;
}
