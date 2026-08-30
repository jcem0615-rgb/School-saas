/**
 * Per-subject attendance: one class, one session, taken by the teacher
 * standing in front of it.
 *
 * The school already had daily gate attendance -- a student scans a QR
 * on the way in and that is the day accounted for. It answers "did they
 * come to school", which is what a truancy report needs, and it cannot
 * answer "were they in Physics", which is what a subject teacher, a
 * failing grade and a worried parent all need.
 *
 * A session is opened when the teacher presses Time In at the start of
 * the class and closed when they press Time Out at the end. Everything
 * here is the arithmetic and the identity rules around that, kept pure
 * so the parts that are easy to get subtly wrong are the parts under
 * test.
 */

/** 'YYYY-MM-DD'. The same shape the daily attendance records use. */
export type DateKey = string;

export type ClassSessionStatus = "open" | "closed";

/**
 * Every student in the section starts here when a session opens.
 *
 * Marking a roll is marking exceptions. A teacher with forty students
 * and three absences should make three taps, not forty, and a default of
 * "unmarked" would mean a session closed in a hurry recorded nothing at
 * all about thirty-seven children who were there.
 */
export const DEFAULT_MARK = "present";

/**
 * One session per timetabled class per day, and the id says so.
 *
 * Deterministic rather than generated, because "press Time In twice"
 * is not a hypothetical -- it is what happens when the first press is
 * slow and the teacher is holding a phone in front of a class. With a
 * generated id that produces two sessions and two half-filled rolls.
 */
export function classSessionId(dateKey: DateKey, scheduleBlockId: string): string {
  return `${dateKey}_${scheduleBlockId}`;
}

/** One mark per student per session, for the same reason. */
export function subjectAttendanceId(sessionId: string, studentId: string): string {
  return `${sessionId}_${studentId}`;
}

/**
 * Monday = 1 through Sunday = 7, matching both `DateTime.weekday` in the
 * app and `dayOfWeek` on a schedule block, so "is this class on today"
 * is a comparison rather than a mapping table.
 *
 * Parsed from the date key rather than taken from a Date, because the
 * key is already in the school's timezone and a Date is in the server's.
 * A session opened at 8am in Manila is the previous evening in UTC, and
 * a weekday derived from that is a day out for every early class.
 */
export function weekdayOfDateKey(dateKey: DateKey): number | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateKey);
  if (!match) return null;
  const [, y, m, d] = match;
  const date = new Date(Date.UTC(Number(y), Number(m) - 1, Number(d)));
  if (Number.isNaN(date.getTime())) return null;
  // getUTCDay is Sunday = 0; shift to Monday = 1..Sunday = 7.
  const day = date.getUTCDay();
  return day === 0 ? 7 : day;
}

/**
 * Whether a roll may still be corrected.
 *
 * The day it was taken, and no longer. A teacher who marked the wrong
 * name should fix it there and then; a register that stays editable for
 * a term is not a record of what happened, it is a record of what
 * somebody last thought. After today it is the registrar's to amend,
 * with the audit trail that implies.
 *
 * Closing the session does *not* end the window. Time Out is "the class
 * is over", not "this is now history", and a teacher who notices at the
 * door that they marked the wrong student absent should not have to ask
 * the office.
 */
export function canEditRoll(sessionDateKey: DateKey, todayKey: DateKey): boolean {
  return sessionDateKey === todayKey;
}

/**
 * Whether this class is timetabled on this date.
 *
 * Checked because "open the session for today's Physics" comes from a
 * screen listing today's classes, and a screen is not a guarantee: a
 * stale list, a phone asleep across midnight, or a request built by
 * hand would otherwise open Monday's session on Tuesday and file the
 * marks under the wrong day.
 */
export function blockRunsOn(blockDayOfWeek: number, dateKey: DateKey): boolean {
  const weekday = weekdayOfDateKey(dateKey);
  return weekday !== null && weekday === blockDayOfWeek;
}

export interface RollCounts {
  present: number;
  late: number;
  absent: number;
  excused: number;
  total: number;
}

/**
 * What the teacher sees at the top of the roll, and what a parent's
 * per-subject rate is built from.
 *
 * Unknown statuses are counted in the total and nowhere else. A mark
 * this build has never heard of is still a student in the class, and
 * dropping them would quietly shrink the denominator of every
 * percentage derived from it.
 */
export function countRoll(marks: Iterable<string>): RollCounts {
  const counts: RollCounts = {present: 0, late: 0, absent: 0, excused: 0, total: 0};
  for (const mark of marks) {
    counts.total += 1;
    if (mark === "present") counts.present += 1;
    else if (mark === "late") counts.late += 1;
    else if (mark === "absent") counts.absent += 1;
    else if (mark === "excused") counts.excused += 1;
  }
  return counts;
}

/**
 * How long the class actually ran, in whole minutes, or null while it is
 * still running.
 *
 * Never negative. A closedAt before the openedAt means the clocks
 * disagreed rather than that the class ran backwards, and a negative
 * duration on a payslip-adjacent record is worse than an absent one.
 */
export function sessionMinutes(openedAt: Date, closedAt: Date | null): number | null {
  if (!closedAt) return null;
  const minutes = Math.round((closedAt.getTime() - openedAt.getTime()) / 60000);
  return minutes < 0 ? 0 : minutes;
}
