import {computeAttendanceStatus, parseCutoffTime} from "../../../src/shared/attendance/attendanceStatus";

describe("computeAttendanceStatus", () => {
  it("marks present when scanning exactly at the cutoff", () => {
    expect(computeAttendanceStatus(7, 30, 7, 30)).toBe("present");
  });

  it("marks present when scanning before the cutoff", () => {
    expect(computeAttendanceStatus(7, 15, 7, 30)).toBe("present");
  });

  it("marks late when scanning even one minute after the cutoff", () => {
    expect(computeAttendanceStatus(7, 31, 7, 30)).toBe("late");
  });

  it("handles cutoffs that cross the hour correctly", () => {
    expect(computeAttendanceStatus(8, 1, 7, 59)).toBe("late");
    expect(computeAttendanceStatus(7, 59, 7, 59)).toBe("present");
  });
});

describe("parseCutoffTime", () => {
  it("parses a valid HH:mm string", () => {
    expect(parseCutoffTime("08:15")).toEqual({hour: 8, minute: 15});
  });

  it("falls back to the default when undefined", () => {
    expect(parseCutoffTime(undefined)).toEqual({hour: 7, minute: 30});
  });

  it("falls back to the default when malformed", () => {
    expect(parseCutoffTime("not-a-time")).toEqual({hour: 7, minute: 30});
  });

  it("respects a custom fallback", () => {
    expect(parseCutoffTime(undefined, "09:00")).toEqual({hour: 9, minute: 0});
  });
});
