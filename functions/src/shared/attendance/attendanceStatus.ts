/**
 * Pure time-of-day comparison, deliberately free of Date/timezone objects
 * so it's trivially unit-testable (see attendanceStatus.test.ts). The
 * caller is responsible for resolving "now" to the school's local
 * hour/minute (see resolveSchoolLocalTime in markAttendance.ts) before
 * calling this.
 */
export function computeAttendanceStatus(
  scanHour: number,
  scanMinute: number,
  cutoffHour: number,
  cutoffMinute: number
): "present" | "late" {
  const scanMinutes = scanHour * 60 + scanMinute;
  const cutoffMinutes = cutoffHour * 60 + cutoffMinute;
  return scanMinutes > cutoffMinutes ? "late" : "present";
}

/** Parses "HH:mm" into {hour, minute}, falling back to a safe default. */
export function parseCutoffTime(cutoff: string | undefined, fallback = "07:30"): {hour: number; minute: number} {
  const raw = cutoff && /^\d{1,2}:\d{2}$/.test(cutoff) ? cutoff : fallback;
  const [hour, minute] = raw.split(":").map(Number);
  return {hour, minute};
}

/**
 * How long somebody has to have been in before a second scan means they
 * are leaving.
 *
 * A gate scanner does not get one clean tap per person. The queue backs
 * up, the beep is missed, the phone is slow, and the same ID goes past
 * it twice inside a few seconds. Without a floor, the second tap is read
 * as a time out: the record then says a person arrived at 07:02 and left
 * at 07:02, and everything downstream believes it.
 *
 * For a student that turns a full day into a zero-minute one. For an
 * hourly employee it is the difference between a day's pay and none --
 * `buildTimesheet` reads exactly these two stamps, and a day with both
 * of them filled in is a day it considers complete, so nothing anywhere
 * flags it.
 *
 * Five minutes. Long enough to swallow a re-scan at the gate, short
 * enough that somebody genuinely turning round and leaving is recorded.
 */
export const MINIMUM_DWELL_MINUTES = 5;

/**
 * What a scan means for a record that already exists.
 *
 * `too_soon` is not an error: the person is already marked in, which is
 * what they were trying to achieve. It is reported so the scanner can
 * say "already timed in" rather than silently doing nothing or, worse,
 * signing them out.
 */
export type RepeatScan = "time_out" | "too_soon" | "already_completed";

export function classifyRepeatScan(
  timestampIn: Date,
  timestampOut: Date | null,
  now: Date,
  minimumDwellMinutes = MINIMUM_DWELL_MINUTES
): RepeatScan {
  if (timestampOut) return "already_completed";
  const minutes = (now.getTime() - timestampIn.getTime()) / 60000;
  // Not `>=`: a scan at exactly the boundary is a person who has been in
  // for the whole window, and refusing it would make the rule read as
  // "more than five minutes" while saying five.
  return minutes >= minimumDwellMinutes ? "time_out" : "too_soon";
}
