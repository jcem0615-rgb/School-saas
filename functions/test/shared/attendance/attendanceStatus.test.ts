import {
  MINIMUM_DWELL_MINUTES,
  classifyRepeatScan,
  computeAttendanceStatus,
  parseCutoffTime,
} from "../../../src/shared/attendance/attendanceStatus";

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

/**
 * A second tap at the gate.
 *
 * The scanner does not get one clean tap per person: the queue backs up,
 * the beep is missed, the phone is slow, and the same ID goes past it
 * twice inside a few seconds. Without a floor the second tap was read as
 * a time out, so the record said somebody arrived at 07:02 and left at
 * 07:02 -- and nothing downstream flagged it, because a record with both
 * stamps filled in is one `buildTimesheet` considers complete. For an
 * hourly employee that is a day's pay.
 */
describe("what a repeat scan means", () => {
  const at = (hhmm: string) => new Date(`2026-06-01T${hhmm}:00Z`);

  it("is a time out once they have actually been in a while", () => {
    expect(classifyRepeatScan(at("07:00"), null, at("16:00"))).toBe("time_out");
  });

  it("is too soon when it is the queue, not somebody leaving", () => {
    expect(classifyRepeatScan(at("07:00"), null, at("07:00"))).toBe("too_soon");
    expect(classifyRepeatScan(at("07:00"), null, at("07:01"))).toBe("too_soon");
    expect(classifyRepeatScan(at("07:00"), null, at("07:04"))).toBe("too_soon");
  });

  it("counts the boundary itself as long enough", () => {
    // The rule says five minutes; refusing at exactly five would make it
    // read as "more than five" while saying five.
    expect(classifyRepeatScan(at("07:00"), null, at("07:05"))).toBe("time_out");
    expect(MINIMUM_DWELL_MINUTES).toBe(5);
  });

  it("is already finished once they have timed out", () => {
    expect(classifyRepeatScan(at("07:00"), at("16:00"), at("16:30"))).toBe(
      "already_completed"
    );
    // Even inside the window: a third tap right after signing out is not
    // a re-entry, it is the same queue again.
    expect(classifyRepeatScan(at("07:00"), at("16:00"), at("16:01"))).toBe(
      "already_completed"
    );
  });

  it("does not sign somebody out on a clock that ran backwards", () => {
    // A device an hour behind would otherwise produce a negative dwell,
    // which is not five minutes and must not be read as one.
    expect(classifyRepeatScan(at("07:00"), null, at("06:30"))).toBe("too_soon");
  });

  it("takes the window as an argument, so a school could set its own", () => {
    expect(classifyRepeatScan(at("07:00"), null, at("07:02"), 1)).toBe("time_out");
    expect(classifyRepeatScan(at("07:00"), null, at("07:20"), 30)).toBe("too_soon");
  });
});
