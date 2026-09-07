import {
  AttendanceScan,
  LeaveWindow,
  MAX_TIMESHEET_DAYS,
  TimesheetError,
  buildTimesheet,
  daysBetween,
  isDateKey,
  isoWeekday,
  minutesOf,
  nextDateKey,
} from "../../../src/shared/payroll/timesheet";

/**
 * The month a payroll clerk reads, on the server.
 *
 * The same claims as `app/test/unit/features/timekeeping/timesheet_test.dart`,
 * against the port. That is the point of them: this is where "did not
 * scan" becomes either absence or approved leave, the decision reaches a
 * payslip, and the two implementations agreeing is what stops a school
 * seeing one figure on the screen and paying another.
 */

const at = (date: string, hour: number) => new Date(`${date}T${String(hour).padStart(2, "0")}:00:00Z`);

function scan(
  date: string,
  opts: {inHour: number; outHour?: number | null; status?: string; personId?: string}
): AttendanceScan {
  return {
    personId: opts.personId ?? "emp_1",
    date,
    timestampIn: at(date, opts.inHour),
    timestampOut: opts.outHour === undefined || opts.outHour === null ? null : at(date, opts.outHour),
    status: opts.status ?? "present",
  };
}

function leave(
  from: string,
  to: string,
  opts: {status?: string; employeeUid?: string} = {}
): LeaveWindow {
  return {
    id: `lv_${from}`,
    employeeUid: opts.employeeUid ?? "emp_1",
    status: opts.status ?? "approved",
    type: "sick",
    fromDate: from,
    toDate: to,
  };
}

// Monday 2 March to Sunday 8 March 2026: a whole week, so every case
// below has both working days and a weekend in it.
function build(opts: {
  records?: AttendanceScan[];
  leaves?: LeaveWindow[];
  fromDate?: string;
  toDate?: string;
  restDays?: ReadonlySet<number>;
} = {}) {
  return buildTimesheet({
    employeeUid: "emp_1",
    employeeName: "Ana Cruz",
    fromDate: opts.fromDate ?? "2026-03-02",
    toDate: opts.toDate ?? "2026-03-08",
    records: opts.records ?? [],
    leaves: opts.leaves ?? [],
    restDays: opts.restDays,
  });
}

describe("a day with no scan", () => {
  it("is absence on a working day", () => {
    const sheet = build();
    expect(sheet.daysAbsent).toBe(5); // Monday to Friday
    expect(sheet.daysWorked).toBe(0);
  });

  it("is a rest day at the weekend, never absence", () => {
    // Five absences in a week is a conversation; seven is an accusation
    // about two days nobody was expected in.
    const weekend = build().days.filter((d) => d.kind === "rest_day");
    expect(weekend.map((d) => d.date)).toEqual(["2026-03-07", "2026-03-08"]);
  });

  it("is leave when an approved request covers it", () => {
    const sheet = build({leaves: [leave("2026-03-03", "2026-03-04")]});
    expect(sheet.daysOnLeave).toBe(2);
    expect(sheet.daysAbsent).toBe(3);
  });

  it("is still absence when the request was only filed", () => {
    // A pending request is a plan. Counting it as leave would let
    // anybody take the day by filing for it.
    const sheet = build({leaves: [leave("2026-03-03", "2026-03-04", {status: "pending"})]});
    expect(sheet.daysOnLeave).toBe(0);
    expect(sheet.daysAbsent).toBe(5);
  });

  it("is still absence when the request was declined", () => {
    const sheet = build({leaves: [leave("2026-03-03", "2026-03-04", {status: "declined"})]});
    expect(sheet.daysAbsent).toBe(5);
  });

  it("ignores a colleague's approved leave", () => {
    const sheet = build({
      leaves: [leave("2026-03-03", "2026-03-04", {employeeUid: "emp_2"})],
    });
    expect(sheet.daysOnLeave).toBe(0);
  });
});

describe("a day with a scan", () => {
  it("counts as worked, with the hours between the scans", () => {
    const sheet = build({records: [scan("2026-03-02", {inHour: 8, outHour: 17})]});
    expect(sheet.daysWorked).toBe(1);
    expect(sheet.minutesWorked).toBe(9 * 60);
  });

  it("counts as late when the scan says so, and still as worked", () => {
    const sheet = build({
      records: [scan("2026-03-02", {inHour: 9, outHour: 17, status: "late"})],
    });
    expect(sheet.daysLate).toBe(1);
    // Late is not absent. Somebody who arrived at nine was at work.
    expect(sheet.daysWorked).toBe(1);
    expect(sheet.daysAbsent).toBe(4);
  });

  it("beats an approved leave for the same day", () => {
    // Somebody who came in on their leave day was at work, whatever the
    // paperwork says.
    const sheet = build({
      records: [scan("2026-03-03", {inHour: 8, outHour: 17})],
      leaves: [leave("2026-03-03", "2026-03-03")],
    });
    expect(sheet.days.find((d) => d.date === "2026-03-03")!.kind).toBe("worked");
    expect(sheet.daysOnLeave).toBe(0);
  });

  it("contributes no hours when nobody scanned out", () => {
    // Not zero-and-silent, and not "until now" either: the system does
    // not know how long they stayed, and inventing hours puts them on a
    // payslip.
    const sheet = build({records: [scan("2026-03-02", {inHour: 8})]});
    expect(sheet.daysWorked).toBe(1);
    expect(sheet.minutesWorked).toBe(0);
    expect(sheet.daysMissingTimeOut).toBe(1);
  });

  it("reports an unclosed day as unknown, not as zero hours", () => {
    // The distinction the aggregate hides: `minutesWorked` adds nothing
    // either way, but "we do not know" and "they worked no hours" are
    // not the same claim, and only one of them can be corrected by
    // asking the employee.
    const sheet = build({records: [scan("2026-03-02", {inHour: 8})]});
    expect(minutesOf(sheet.days[0])).toBeNull();

    const closed = build({records: [scan("2026-03-02", {inHour: 8, outHour: 17})]});
    expect(minutesOf(closed.days[0])).toBe(540);
  });

  it("takes the earlier arrival when a day somehow has two records", () => {
    const sheet = build({
      records: [
        scan("2026-03-02", {inHour: 11, outHour: 17}),
        scan("2026-03-02", {inHour: 8, outHour: 17}),
      ],
    });
    expect(sheet.days.find((d) => d.date === "2026-03-02")!.timeIn!.getUTCHours()).toBe(8);
  });

  it("ignores another employee entirely", () => {
    const sheet = build({
      records: [scan("2026-03-02", {inHour: 8, outHour: 17, personId: "emp_2"})],
    });
    expect(sheet.daysWorked).toBe(0);
    expect(sheet.daysAbsent).toBe(5);
  });

  it("never counts more than a day's minutes from one scan pair", () => {
    // A scan-out somebody entered for the wrong day would otherwise pay
    // an hourly employee for a week in one row.
    const sheet = build({
      records: [
        {
          personId: "emp_1",
          date: "2026-03-02",
          timestampIn: at("2026-03-02", 8),
          timestampOut: at("2026-03-06", 17),
          status: "present",
        },
      ],
    });
    expect(sheet.minutesWorked).toBe(24 * 60);
  });
});

describe("the shape of the week", () => {
  it("covers every day between the bounds, inclusive", () => {
    const sheet = build();
    expect(sheet.days).toHaveLength(7);
    expect(sheet.days[0].date).toBe("2026-03-02");
    expect(sheet.days[6].date).toBe("2026-03-08");
  });

  it("honours a school that works Saturdays", () => {
    // Reporting every Saturday as absence would make the sheet useless
    // for a school that runs Saturday classes.
    const sheet = build({restDays: new Set([7])});
    expect(sheet.workingDays).toBe(6);
    expect(sheet.days.filter((d) => d.kind === "rest_day")).toHaveLength(1);
  });

  it("a single day is a single row", () => {
    expect(build({fromDate: "2026-03-02", toDate: "2026-03-02"}).days).toHaveLength(1);
  });

  it("crosses a month boundary, February included", () => {
    // 2028 is a leap year, so this range has a 29th in it. The client
    // gets this right by walking DateTimes; this walks the keys.
    const sheet = build({fromDate: "2028-02-27", toDate: "2028-03-02"});
    expect(sheet.days.map((d) => d.date)).toEqual([
      "2028-02-27",
      "2028-02-28",
      "2028-02-29",
      "2028-03-01",
      "2028-03-02",
    ]);
  });

  it("refuses a period that runs backwards", () => {
    expect(() => build({fromDate: "2026-03-08", toDate: "2026-03-02"})).toThrow(
      TimesheetError
    );
  });

  it("refuses a period longer than a payroll period can be", () => {
    // A mistyped year is what asks for one. Building 3,600 days for
    // forty people is a function that times out rather than one that
    // says no.
    expect(() => build({fromDate: "2026-01-01", toDate: "2026-12-31"})).toThrow(
      TimesheetError
    );
    expect(MAX_TIMESHEET_DAYS).toBeGreaterThanOrEqual(31);
  });

  it("refuses a date that is not one", () => {
    for (const bad of ["2026-3-2", "not-a-date", "2026-02-31", ""]) {
      expect(() => build({fromDate: bad})).toThrow(TimesheetError);
    }
  });
});

describe("the date arithmetic underneath", () => {
  it("reads a weekday the way Dart numbers them", () => {
    // 1 = Monday ... 7 = Sunday. Getting this off by one would report
    // every Sunday as an absence and every Monday as a rest day.
    expect(isoWeekday("2026-03-02")).toBe(1);
    expect(isoWeekday("2026-03-07")).toBe(6);
    expect(isoWeekday("2026-03-08")).toBe(7);
  });

  it("rolls over a month and a leap February", () => {
    expect(nextDateKey("2026-03-31")).toBe("2026-04-01");
    expect(nextDateKey("2026-12-31")).toBe("2027-01-01");
    expect(nextDateKey("2028-02-28")).toBe("2028-02-29");
    expect(nextDateKey("2026-02-28")).toBe("2026-03-01");
  });

  it("counts days inclusively, and zero for a range that runs backwards", () => {
    expect(daysBetween("2026-03-02", "2026-03-02")).toBe(1);
    expect(daysBetween("2026-03-02", "2026-03-08")).toBe(7);
    expect(daysBetween("2026-03-08", "2026-03-02")).toBe(0);
  });

  it("knows a real date from a well-shaped one", () => {
    expect(isDateKey("2026-02-28")).toBe(true);
    expect(isDateKey("2026-02-29")).toBe(false); // 2026 is not a leap year
    expect(isDateKey("2028-02-29")).toBe(true);
    expect(isDateKey("2026-13-01")).toBe(false);
    expect(isDateKey(20260301)).toBe(false);
  });
});
