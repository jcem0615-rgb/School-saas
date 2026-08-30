import {
  blockRunsOn,
  canEditRoll,
  classSessionId,
  countRoll,
  sessionMinutes,
  subjectAttendanceId,
  weekdayOfDateKey,
} from "../../../src/shared/attendance/classSession";

describe("identity", () => {
  it("gives one session per class per day", () => {
    // The property that makes pressing Time In twice harmless.
    expect(classSessionId("2026-03-03", "blk_1")).toBe(
      classSessionId("2026-03-03", "blk_1")
    );
    expect(classSessionId("2026-03-03", "blk_1")).not.toBe(
      classSessionId("2026-03-04", "blk_1")
    );
    expect(classSessionId("2026-03-03", "blk_1")).not.toBe(
      classSessionId("2026-03-03", "blk_2")
    );
  });

  it("gives one mark per student per session", () => {
    const session = classSessionId("2026-03-03", "blk_1");
    expect(subjectAttendanceId(session, "stu_1")).toBe(
      subjectAttendanceId(session, "stu_1")
    );
    expect(subjectAttendanceId(session, "stu_1")).not.toBe(
      subjectAttendanceId(session, "stu_2")
    );
  });
});

describe("weekdayOfDateKey", () => {
  it("is Monday = 1 through Sunday = 7", () => {
    expect(weekdayOfDateKey("2026-03-02")).toBe(1); // a Monday
    expect(weekdayOfDateKey("2026-03-06")).toBe(5); // that Friday
    expect(weekdayOfDateKey("2026-03-08")).toBe(7); // that Sunday
  });

  it("refuses anything that is not a date key", () => {
    expect(weekdayOfDateKey("")).toBeNull();
    expect(weekdayOfDateKey("3 March 2026")).toBeNull();
    expect(weekdayOfDateKey("2026-3-2")).toBeNull();
  });
});

describe("blockRunsOn", () => {
  it("lets Monday's class open on a Monday", () => {
    expect(blockRunsOn(1, "2026-03-02")).toBe(true);
  });

  it("refuses to open Monday's class on Tuesday", () => {
    // The failure this exists for: a stale "today's classes" list on a
    // phone that slept through midnight would otherwise file a day's
    // marks under the wrong date.
    expect(blockRunsOn(1, "2026-03-03")).toBe(false);
  });

  it("refuses an unparseable date rather than guessing", () => {
    expect(blockRunsOn(1, "tomorrow")).toBe(false);
  });
});

describe("canEditRoll", () => {
  it("allows corrections on the day the class was taken", () => {
    expect(canEditRoll("2026-03-03", "2026-03-03")).toBe(true);
  });

  it("does not allow yesterday's register to be rewritten", () => {
    expect(canEditRoll("2026-03-02", "2026-03-03")).toBe(false);
  });
});

describe("countRoll", () => {
  it("counts each status", () => {
    expect(countRoll(["present", "present", "late", "absent", "excused"])).toEqual({
      present: 2,
      late: 1,
      absent: 1,
      excused: 1,
      total: 5,
    });
  });

  it("counts a mark it does not recognise in the total and nowhere else", () => {
    // Otherwise a status added later quietly shrinks the denominator of
    // every attendance percentage built on this.
    const counts = countRoll(["present", "on_field_trip"]);
    expect(counts.total).toBe(2);
    expect(counts.present).toBe(1);
    expect(counts.late + counts.absent + counts.excused).toBe(0);
  });

  it("has a total of zero for an empty class", () => {
    expect(countRoll([]).total).toBe(0);
  });
});

describe("sessionMinutes", () => {
  it("is null while the class is still running", () => {
    expect(sessionMinutes(new Date("2026-03-03T01:00:00Z"), null)).toBeNull();
  });

  it("is the whole minutes between Time In and Time Out", () => {
    expect(
      sessionMinutes(
        new Date("2026-03-03T01:00:00Z"),
        new Date("2026-03-03T01:55:00Z")
      )
    ).toBe(55);
  });

  it("is never negative when the clocks disagree", () => {
    expect(
      sessionMinutes(
        new Date("2026-03-03T01:00:00Z"),
        new Date("2026-03-03T00:58:00Z")
      )
    ).toBe(0);
  });
});
