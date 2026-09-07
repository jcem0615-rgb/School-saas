import {
  ContributionScheme,
  ContributionTable,
  contributionOn,
  canIssuePayslips,
  round2,
  schemeFromDoc,
  tableFor,
  unconfiguredKinds,
} from "../../../src/shared/payroll/contributions";
import {
  Compensation,
  Payslip,
  compensationFromDoc,
  computePayslip,
  dailyRate,
  monthlyBasisFor,
  thirteenthMonthPay,
} from "../../../src/shared/payroll/payslip";
import {AttendanceScan, Timesheet, buildTimesheet} from "../../../src/shared/payroll/timesheet";

/**
 * Somebody's salary, on the server.
 *
 * The same claims as `app/test/unit/features/payroll/domain/payslip_test.dart`,
 * against the port that a real deployment actually runs. Every case here
 * is money out of a person's pay: a deduction that is wrong high is a
 * teacher short at the end of the month; one that is wrong low is a
 * school under-remitting to three agencies and an employee handed a bill
 * at the end of the year.
 */

// A fortnight: ten working days, Mon 1 June to Fri 12 June 2026.
const FROM = "2026-06-01";
const TO = "2026-06-12";
const WORKED = [1, 2, 3, 4, 5, 8, 9, 10, 11, 12];

function scan(day: number, opts: {inHour?: number; outHour?: number | null; status?: string} = {}): AttendanceScan {
  const date = `2026-06-${String(day).padStart(2, "0")}`;
  const outHour = opts.outHour === undefined ? 16 : opts.outHour;
  return {
    personId: "emp_1",
    date,
    timestampIn: new Date(`${date}T${String(opts.inHour ?? 7).padStart(2, "0")}:00:00Z`),
    timestampOut: outHour === null ? null : new Date(`${date}T${String(outHour).padStart(2, "0")}:00:00Z`),
    status: opts.status ?? "present",
  };
}

/** A full fortnight, every working day scanned nine hours. */
function fortnight(records?: AttendanceScan[]): Timesheet {
  return buildTimesheet({
    employeeUid: "emp_1",
    employeeName: "Maria Santos",
    fromDate: FROM,
    toDate: TO,
    records: records ?? WORKED.map((d) => scan(d)),
    leaves: [],
  });
}

const monthly: Compensation = {
  employeeUid: "emp_1",
  employeeName: "Maria Santos",
  basis: "monthly",
  rate: 30000,
  allowance: 0,
  deductAbsences: true,
};

/**
 * A deliberately simple scheme, so the arithmetic under test is the
 * payslip's and not the tables'.
 */
const scheme: ContributionScheme = {
  confirmedBySchool: true,
  confirmedByName: "Office",
  tables: [
    {
      kind: "sss",
      sourceLabel: "SSS Circular (school-entered)",
      brackets: [bracket({from: 0, fixedAmount: 1350, employerFixedAmount: 2650})],
    },
    {
      kind: "philhealth",
      sourceLabel: null,
      brackets: [bracket({from: 0, percentOfExcess: 2.5, employerPercentOfExcess: 2.5})],
    },
    {
      kind: "pagibig",
      sourceLabel: null,
      brackets: [bracket({from: 0, fixedAmount: 200, employerFixedAmount: 200})],
    },
    {
      kind: "withholding_tax",
      sourceLabel: "RR (school-entered)",
      brackets: [
        bracket({from: 0, to: 20833}),
        bracket({from: 20833.01, percentOfExcess: 15}),
      ],
    },
  ],
};

function bracket(over: Partial<ContributionTable["brackets"][number]> & {from: number}) {
  return {
    to: null,
    fixedAmount: 0,
    percentOfExcess: 0,
    employerFixedAmount: 0,
    employerPercentOfExcess: 0,
    ...over,
  };
}

function compute(opts: {
  who?: Compensation;
  sheet?: Timesheet;
  using?: ContributionScheme;
  monthlyBasis?: number;
  deductContributions?: boolean;
} = {}): Payslip {
  return computePayslip({
    compensation: opts.who ?? monthly,
    timesheet: opts.sheet ?? fortnight(),
    scheme: opts.using ?? scheme,
    monthlyBasisForContributions: opts.monthlyBasis ?? 30000,
    deductContributions: opts.deductContributions,
  });
}

/** The fortnight with the first [count] working days unscanned. */
function withAbsences(count: number): Timesheet {
  return buildTimesheet({
    employeeUid: "emp_1",
    employeeName: "Maria Santos",
    fromDate: FROM,
    toDate: TO,
    records: WORKED.slice(count).map((d) => scan(d)),
    leaves: [],
  });
}

describe("what somebody earns", () => {
  it("a monthly salary is the salary, whatever the month held", () => {
    const slip = compute();
    expect(slip.earnings[0].label).toBe("Basic pay");
    expect(slip.earnings[0].amount).toBe(30000);
  });

  it("a daily rate is the days actually worked", () => {
    const slip = compute({who: {...monthly, basis: "daily", rate: 900}});
    expect(slip.daysWorked).toBe(10);
    expect(slip.earnings[0].amount).toBe(9000);
    expect(slip.earnings[0].basis).toContain("10 days");
  });

  it("an hourly rate is the hours the scans actually show", () => {
    // Ten days of nine hours.
    const slip = compute({who: {...monthly, basis: "hourly", rate: 400}});
    expect(slip.earnings[0].amount).toBe(36000);
  });

  it("an allowance is paid but kept out of the basic", () => {
    // 13th month and the contribution brackets are reckoned on basic
    // pay, so an allowance folded into it would inflate both.
    const slip = compute({who: {...monthly, allowance: 2000}});
    expect(slip.basicPay).toBe(30000);
    expect(slip.grossPay).toBe(32000);
  });
});

describe("a day nobody worked", () => {
  it("comes off a monthly salary at the period day rate", () => {
    // Ten working days in the period, so a day is 3,000.
    const slip = compute({sheet: withAbsences(2)});
    expect(slip.daysAbsent).toBe(2);
    expect(slip.deductions.find((d) => d.label === "Absences")!.amount).toBe(6000);
    expect(slip.basicPay).toBe(24000);
  });

  it("does not come off when the contract simply pays the month", () => {
    // A school that deducts anyway is making a decision this software
    // should not make for it.
    const slip = compute({
      who: {...monthly, deductAbsences: false},
      sheet: withAbsences(2),
    });
    expect(slip.deductions.some((d) => d.label === "Absences")).toBe(false);
    expect(slip.basicPay).toBe(30000);
  });

  it("is never deducted twice from hourly pay", () => {
    // The unworked hours were never in the total to begin with.
    const slip = compute({
      who: {...monthly, basis: "hourly", rate: 400},
      sheet: withAbsences(2),
    });
    expect(slip.deductions.some((d) => d.label === "Absences")).toBe(false);
    expect(slip.basicPay).toBe(400 * 8 * 9);
  });

  it("is not deducted at all when the period had no working days", () => {
    // A divisor of zero is a period nobody was expected in. Dividing by
    // it would put an infinity on a payslip.
    const weekend = buildTimesheet({
      employeeUid: "emp_1",
      employeeName: "Maria Santos",
      fromDate: "2026-06-06",
      toDate: "2026-06-07",
      records: [],
      leaves: [],
    });
    expect(weekend.workingDays).toBe(0);
    const slip = compute({sheet: weekend});
    expect(slip.netPay).toBeGreaterThan(0);
    expect(Number.isFinite(slip.netPay)).toBe(true);
  });
});

describe("what the school cannot know", () => {
  it("a day scanned in and never out is flagged, not guessed at", () => {
    const slip = compute({
      sheet: fortnight([
        ...WORKED.slice(0, 9).map((d) => scan(d)),
        scan(12, {outHour: null}),
      ]),
    });
    expect(slip.daysMissingTimeOut).toBe(1);
  });

  it("lateness is counted and not deducted", () => {
    // The timesheet knows the day was late, not by how much. Deducting
    // a made-up number of minutes is worse than saying so.
    const slip = compute({
      sheet: fortnight([
        scan(1, {inHour: 9, status: "late"}),
        ...WORKED.slice(1).map((d) => scan(d)),
      ]),
    });
    expect(slip.daysLate).toBe(1);
    expect(slip.deductions.some((d) => d.label.toLowerCase().includes("late"))).toBe(false);
  });
});

describe("what comes off", () => {
  it("the three agencies, then tax on what is left", () => {
    const slip = compute();
    expect(slip.deductions.map((d) => d.label)).toEqual([
      "SSS",
      "PhilHealth",
      "Pag-IBIG",
      "Withholding tax",
    ]);
    // 30,000 - 1,350 - 750 - 200 = 27,700 taxable.
    // 15% of the excess over 20,833.01 = 1,030.05.
    expect(slip.deductions[3].amount).toBeCloseTo(1030.05, 2);
  });

  it("tax is computed after the contributions, not before", () => {
    // The whole reason they are done in that order. Taxing the gross
    // would take more from everybody, every month.
    const taxOnly: ContributionScheme = {
      confirmedBySchool: true,
      confirmedByName: null,
      tables: [scheme.tables[3]],
    };
    expect(compute().deductions[3].amount).toBeLessThan(
      compute({using: taxOnly}).deductions[0].amount
    );
  });

  it("nothing at all on the first cut-off of a semi-monthly month", () => {
    // Deducting the month's contributions on both cut-offs would take
    // double from everybody on semi-monthly pay.
    const slip = compute({deductContributions: false});
    expect(slip.deductions).toEqual([]);
    expect(slip.netPay).toBe(30000);
  });

  it("the employer share is carried, though it is not on the payslip", () => {
    // It never reaches the employee and it is what the school remits.
    expect(compute().employerContributions).toBeCloseTo(2650 + 750 + 200, 2);
  });

  it("the deduction lines say where the number came from", () => {
    // A deduction an employee cannot trace is one they take on trust.
    expect(compute().deductions.find((d) => d.label === "SSS")!.basis).toContain(
      "SSS Circular"
    );
  });

  it("net pay never goes below zero", () => {
    // A table that would take more than somebody earned is a
    // misconfiguration, not a negative payslip.
    const slip = compute({who: {...monthly, rate: 500}, monthlyBasis: 500});
    expect(slip.netPay).toBeGreaterThanOrEqual(0);
  });

  it("an absence is not counted against the tax base twice", () => {
    // Tax is reckoned on the basic after absences, and the absence line
    // is excluded from the agency total that comes off it.
    const slip = compute({sheet: withAbsences(2)});
    const agencies = slip.deductions
      .filter((d) => d.label !== "Absences" && d.label !== "Withholding tax")
      .reduce((sum, d) => sum + d.amount, 0);
    const taxable = round2(24000 - agencies);
    expect(slip.deductions.find((d) => d.label === "Withholding tax")!.amount)
      .toBeCloseTo(round2(((taxable - 20833.01) * 15) / 100), 2);
  });
});

describe("the contribution tables themselves", () => {
  it("an unconfigured agency deducts nothing rather than throwing", () => {
    // A half-configured school can still see what the figures would be
    // while they work through it; issuing refuses elsewhere.
    const empty: ContributionScheme = {tables: [], confirmedBySchool: false, confirmedByName: null};
    expect(contributionOn(tableFor(empty, "sss"), 30000).employeeShare).toBe(0);
  });

  it("a salary above every bracket takes the top one", () => {
    // Deducting nothing from the highest earner in the school is a
    // worse way to find a stale ceiling than deducting the maximum.
    const table: ContributionTable = {
      kind: "sss",
      sourceLabel: null,
      brackets: [
        bracket({from: 0, to: 20000, fixedAmount: 900}),
        bracket({from: 20000.01, to: 30000, fixedAmount: 1350}),
      ],
    };
    expect(contributionOn(table, 90000).employeeShare).toBe(1350);
  });

  it("a salary below every bracket owes nothing", () => {
    const table: ContributionTable = {
      kind: "sss",
      sourceLabel: null,
      brackets: [bracket({from: 5000, to: 20000, fixedAmount: 900})],
    };
    expect(contributionOn(table, 1000).employeeShare).toBe(0);
  });

  it("a scheme is not usable until it is both complete and confirmed", () => {
    const nothing: ContributionScheme = {tables: [], confirmedBySchool: false, confirmedByName: null};
    expect(canIssuePayslips(nothing)).toBe(false);
    expect(unconfiguredKinds(nothing)).toHaveLength(4);

    const typedButUnconfirmed: ContributionScheme = {
      confirmedBySchool: false,
      confirmedByName: null,
      tables: scheme.tables,
    };
    expect(unconfiguredKinds(typedButUnconfirmed)).toHaveLength(0);
    expect(canIssuePayslips(typedButUnconfirmed)).toBe(false);
    expect(canIssuePayslips({...typedButUnconfirmed, confirmedBySchool: true})).toBe(true);
  });

  it("reads a scheme off a document, and an absent one as empty", () => {
    expect(unconfiguredKinds(schemeFromDoc(undefined))).toHaveLength(4);
    const read = schemeFromDoc({
      confirmedBySchool: true,
      confirmedByName: "Office",
      tables: [
        {kind: "sss", sourceLabel: "Circular", brackets: [{from: 0, fixedAmount: 1350}]},
        // Not a kind this system knows. Dropped rather than guessed at.
        {kind: "coffee_fund", brackets: [{from: 0, fixedAmount: 50}]},
      ],
    });
    expect(read.tables).toHaveLength(1);
    expect(contributionOn(tableFor(read, "sss"), 30000).employeeShare).toBe(1350);
  });
});

describe("what a compensation document says", () => {
  it("defaults to deducting absences when the school has not said", () => {
    // The common arrangement, and the same default as the entity.
    expect(compensationFromDoc("emp_1", {rate: 30000}).deductAbsences).toBe(true);
    expect(compensationFromDoc("emp_1", {rate: 30000, deductAbsences: false}).deductAbsences)
      .toBe(false);
  });

  it("reads an unusable rate as nothing rather than NaN", () => {
    // A NaN rate propagates into every figure on the payslip and prints
    // as "NaN" beside somebody's name.
    expect(compensationFromDoc("emp_1", {rate: "lots"}).rate).toBe(0);
    expect(compensationFromDoc("emp_1", undefined).rate).toBe(0);
  });

  it("falls back to a monthly basis for an unknown one", () => {
    expect(compensationFromDoc("emp_1", {basis: "annually"}).basis).toBe("monthly");
  });
});

describe("the figures the tables are read with", () => {
  it("uses the monthly salary, not what this period pays", () => {
    // A semi-monthly payslip still deducts against the monthly bracket.
    expect(monthlyBasisFor(monthly)).toBe(30000);
  });

  it("turns a daily and an hourly rate into an approximate month", () => {
    expect(monthlyBasisFor({...monthly, basis: "daily", rate: 900})).toBe(19800);
    expect(monthlyBasisFor({...monthly, basis: "hourly", rate: 400})).toBe(70400);
  });

  it("divides a monthly salary by the period's own working days", () => {
    // Not a fixed 22 or 26: a fixed divisor pays a short February
    // differently from a long March for no reason anybody can explain.
    expect(dailyRate(monthly, 10)).toBe(3000);
    expect(dailyRate(monthly, 22)).toBeCloseTo(1363.64, 2);
    expect(dailyRate({...monthly, basis: "daily", rate: 900}, 10)).toBe(900);
    expect(dailyRate({...monthly, basis: "hourly", rate: 400}, 10)).toBe(0);
    expect(dailyRate(monthly, 0)).toBe(0);
  });
});

describe("the 13th month", () => {
  it("is a twelfth of the basic actually earned", () => {
    // PD 851. Not a bonus, not optional, and not on the allowances.
    expect(thirteenthMonthPay(Array.from({length: 12}, () => compute()))).toBe(30000);
  });

  it("is a twelfth of what a mid-year joiner earned, not of a full year", () => {
    expect(thirteenthMonthPay(Array.from({length: 5}, () => compute()))).toBe(12500);
  });

  it("leaves allowances out of it", () => {
    const year = Array.from({length: 12}, () =>
      compute({who: {...monthly, allowance: 5000}})
    );
    expect(thirteenthMonthPay(year)).toBe(30000);
  });
});

describe("rounding", () => {
  it("goes to two places, a half away from zero", () => {
    // `Math.round` rounds a half towards positive infinity, so -12.5
    // would come back as -12 where Dart gives -13. Checked on a value
    // that is exactly representable: 1.005 is not, and *both*
    // implementations round it down for that reason rather than either
    // one being wrong.
    expect(round2(0.125)).toBe(0.13);
    expect(round2(-0.125)).toBe(-0.13);
    expect(round2(1030.0485)).toBe(1030.05);
    expect(round2(1.005)).toBe(1); // as Dart does, for the same reason
  });

  it("never produces a negative zero", () => {
    // The one deliberate divergence from the Dart copy, which returns
    // -0.0 here. Numerically identical -- -0.0 equals 0 -- but it prints
    // as "-0.00", and a payslip line reading minus nothing is a support
    // call.
    expect(Object.is(round2(-0.001), 0)).toBe(true);
  });
});
