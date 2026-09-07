/**
 * One employee's month, assembled from their scans and their leave.
 *
 * A port of `app/lib/features/timekeeping/domain/entities/timesheet.dart`,
 * and it has to stay one: this is the part that decides whether a day
 * with no scan is approved leave, a Saturday, or an absence that comes
 * off somebody's pay. Two implementations of that decision are two
 * answers to "why was I docked a day".
 *
 * The one deliberate divergence is dates. The Dart version walks
 * `DateTime`s, which are local to whoever is looking; this walks the
 * 'YYYY-MM-DD' keys themselves, because the server runs in UTC and a
 * school in Manila must not get a different March depending on where the
 * function happened to be scheduled. The keys are the same keys
 * `markAttendance` writes, so no conversion happens anywhere.
 */

/** What one day came to. */
export type WorkDayKind = "worked" | "late" | "on_leave" | "absent" | "rest_day";

/** A scan, as it comes off an attendance document. */
export interface AttendanceScan {
  personId: string;
  /** 'YYYY-MM-DD'. */
  date: string;
  timestampIn: Date;
  timestampOut: Date | null;
  /** 'present' | 'late' | 'absent' | 'excused'. */
  status: string;
}

/** A leave request, as it comes off a leaveRequests document. */
export interface LeaveWindow {
  id: string;
  employeeUid: string;
  /** 'pending' | 'approved' | 'declined' | 'cancelled'. */
  status: string;
  type: string;
  /** Inclusive 'YYYY-MM-DD' bounds. */
  fromDate: string;
  toDate: string;
}

export interface TimesheetDay {
  date: string;
  kind: WorkDayKind;
  timeIn: Date | null;
  timeOut: Date | null;
  /** The leave covering the day, when one does. */
  leaveId: string | null;
  leaveType: string | null;
}

export interface Timesheet {
  employeeUid: string;
  employeeName: string;
  fromDate: string;
  toDate: string;
  days: TimesheetDay[];

  daysWorked: number;
  daysLate: number;
  daysOnLeave: number;
  daysAbsent: number;
  /** Everything that is not a rest day, which is the divisor a day's pay is worked out from. */
  workingDays: number;
  minutesWorked: number;
  daysMissingTimeOut: number;
}

const DATE_KEY = /^\d{4}-\d{2}-\d{2}$/;

export function isDateKey(value: unknown): value is string {
  if (typeof value !== "string" || !DATE_KEY.test(value)) return false;
  // '2025-02-31' matches the pattern and is not a day. Round-tripping
  // through UTC is what catches it.
  const [y, m, d] = value.split("-").map(Number);
  const at = new Date(Date.UTC(y, m - 1, d));
  return at.getUTCFullYear() === y && at.getUTCMonth() === m - 1 && at.getUTCDate() === d;
}

/** 1 = Monday ... 7 = Sunday, matching Dart's `DateTime.weekday`. */
export function isoWeekday(dateKey: string): number {
  const [y, m, d] = dateKey.split("-").map(Number);
  const sundayFirst = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  return sundayFirst === 0 ? 7 : sundayFirst;
}

/** The next 'YYYY-MM-DD', month and leap year included. */
export function nextDateKey(dateKey: string): string {
  const [y, m, d] = dateKey.split("-").map(Number);
  const at = new Date(Date.UTC(y, m - 1, d + 1));
  return [
    String(at.getUTCFullYear()).padStart(4, "0"),
    String(at.getUTCMonth() + 1).padStart(2, "0"),
    String(at.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

/** Inclusive count of days between two keys, or 0 for a range that runs backwards. */
export function daysBetween(fromDate: string, toDate: string): number {
  if (fromDate > toDate) return 0;
  const at = (key: string) => {
    const [y, m, d] = key.split("-").map(Number);
    return Date.UTC(y, m - 1, d);
  };
  return Math.round((at(toDate) - at(fromDate)) / 86_400_000) + 1;
}

/** The keys the school does not work. 6 = Saturday, 7 = Sunday. */
export const DEFAULT_REST_DAYS: ReadonlySet<number> = new Set([6, 7]);

/**
 * A ceiling on how long a timesheet may be.
 *
 * Nothing legitimate asks for one; a mistyped year is what asks for one,
 * and building 3,600 days for forty people is a function that times out
 * rather than a function that says no.
 */
export const MAX_TIMESHEET_DAYS = 62;

export class TimesheetError extends Error {}

export function buildTimesheet(input: {
  employeeUid: string;
  employeeName: string;
  fromDate: string;
  toDate: string;
  records: Iterable<AttendanceScan>;
  leaves: Iterable<LeaveWindow>;
  restDays?: ReadonlySet<number>;
}): Timesheet {
  const {employeeUid, employeeName, fromDate, toDate} = input;
  const restDays = input.restDays ?? DEFAULT_REST_DAYS;

  if (!isDateKey(fromDate) || !isDateKey(toDate)) {
    throw new TimesheetError("A payroll period needs two real dates.");
  }
  const span = daysBetween(fromDate, toDate);
  if (span === 0) {
    throw new TimesheetError("A payroll period cannot end before it starts.");
  }
  if (span > MAX_TIMESHEET_DAYS) {
    throw new TimesheetError(
      `A payroll period cannot run longer than ${MAX_TIMESHEET_DAYS} days.`
    );
  }

  // One record per person per day is the invariant markAttendance keeps
  // through its derived id. Where two somehow exist, the earlier time in
  // is the one that counts -- that is when they arrived.
  const byDate = new Map<string, AttendanceScan>();
  for (const record of input.records) {
    if (record.personId !== employeeUid) continue;
    const existing = byDate.get(record.date);
    if (!existing || record.timestampIn < existing.timestampIn) {
      byDate.set(record.date, record);
    }
  }

  // Only approved leave counts. A pending request is a plan, and a
  // declined one is a day somebody was expected in.
  const approved = [...input.leaves].filter(
    (l) => l.employeeUid === employeeUid && l.status === "approved"
  );

  const days: TimesheetDay[] = [];
  for (let key = fromDate; key <= toDate; key = nextDateKey(key)) {
    const record = byDate.get(key);
    // String comparison works because the keys are zero-padded ISO dates.
    const leave = approved.find((l) => key >= l.fromDate && key <= l.toDate) ?? null;

    let kind: WorkDayKind;
    if (record) {
      // A scan beats everything. Somebody who came in on their approved
      // leave day was at work, and the record says so.
      kind = record.status === "late" ? "late" : "worked";
    } else if (leave) {
      kind = "on_leave";
    } else if (restDays.has(isoWeekday(key))) {
      kind = "rest_day";
    } else {
      kind = "absent";
    }

    days.push({
      date: key,
      kind,
      timeIn: record?.timestampIn ?? null,
      timeOut: record?.timestampOut ?? null,
      leaveId: leave?.id ?? null,
      leaveType: leave?.type ?? null,
    });
  }

  return {
    employeeUid,
    employeeName,
    fromDate,
    toDate,
    days,
    daysWorked: days.filter((d) => d.kind === "worked" || d.kind === "late").length,
    daysLate: days.filter((d) => d.kind === "late").length,
    daysOnLeave: days.filter((d) => d.kind === "on_leave").length,
    daysAbsent: days.filter((d) => d.kind === "absent").length,
    workingDays: days.filter((d) => d.kind !== "rest_day").length,
    minutesWorked: days.reduce((sum, day) => sum + (minutesOf(day) ?? 0), 0),
    daysMissingTimeOut: days.filter((d) => d.timeIn !== null && d.timeOut === null).length,
  };
}

/**
 * Minutes between the scans, or null when one of them is missing.
 *
 * A day with a time in and no time out is deliberately null rather than
 * zero or "until now": somebody forgot to scan out, and the honest
 * answer is that this system does not know how long they stayed.
 * Guessing would put invented hours on a payslip.
 */
export function minutesOf(day: TimesheetDay): number | null {
  if (!day.timeIn || !day.timeOut) return null;
  const minutes = Math.floor((day.timeOut.getTime() - day.timeIn.getTime()) / 60_000);
  return Math.min(Math.max(minutes, 0), 60 * 24);
}
