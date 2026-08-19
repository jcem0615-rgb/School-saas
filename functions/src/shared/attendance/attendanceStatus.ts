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
