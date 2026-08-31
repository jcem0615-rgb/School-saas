import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/payroll/domain/entities/contribution_scheme.dart';
import 'package:logicclass/features/payroll/domain/entities/payslip.dart';
import 'package:logicclass/features/qr_attendance/domain/entities/attendance_record.dart';
import 'package:logicclass/features/timekeeping/domain/entities/timesheet.dart';

/// Somebody's salary.
///
/// Every case here is money out of a person's pay. A deduction that is
/// wrong high is a teacher short at the end of the month; one that is
/// wrong low is a school under-remitting to three agencies and an
/// employee handed a bill at the end of the year. The arithmetic is not
/// clever -- what these test is the handful of decisions around the
/// edges of it, and that none of them was made silently.
void main() {
  // A fortnight: ten working days, Mon 1 June to Fri 12 June 2026.
  final from = DateTime(2026, 6, 1);
  final to = DateTime(2026, 6, 12);

  AttendanceRecord scan(int day, {int inHour = 7, int? outHour = 16}) =>
      AttendanceRecord(
        id: 'att_$day',
        personId: 'emp_1',
        personRole: 'faculty',
        subjectType: AttendanceSubjectType.employee,
        date: '2026-06-${day.toString().padLeft(2, '0')}',
        timestampIn: DateTime(2026, 6, day, inHour, 0),
        timestampOut: outHour == null ? null : DateTime(2026, 6, day, outHour, 0),
        status: AttendanceStatus.present,
      );

  /// A full fortnight, every working day scanned nine hours.
  Timesheet fullFortnight({List<AttendanceRecord>? records}) => buildTimesheet(
        employeeUid: 'emp_1',
        employeeName: 'Maria Santos',
        from: from,
        to: to,
        records: records ??
            [for (final d in [1, 2, 3, 4, 5, 8, 9, 10, 11, 12]) scan(d)],
        leaves: const [],
      );

  const monthly = Compensation(
    employeeUid: 'emp_1',
    employeeName: 'Maria Santos',
    basis: PayBasis.monthly,
    rate: 30000,
  );

  /// A deliberately simple scheme, so the arithmetic under test is the
  /// payslip's and not the tables'.
  const scheme = ContributionScheme(
    confirmedBySchool: true,
    tables: [
      ContributionTable(
        kind: ContributionKind.sss,
        sourceLabel: 'SSS Circular (school-entered)',
        brackets: [
          ContributionBracket(
            from: 0,
            fixedAmount: 1350,
            employerFixedAmount: 2650,
          ),
        ],
      ),
      ContributionTable(
        kind: ContributionKind.philHealth,
        brackets: [
          ContributionBracket(from: 0, percentOfExcess: 2.5, employerPercentOfExcess: 2.5),
        ],
      ),
      ContributionTable(
        kind: ContributionKind.pagIbig,
        brackets: [ContributionBracket(from: 0, fixedAmount: 200, employerFixedAmount: 200)],
      ),
      ContributionTable(
        kind: ContributionKind.withholdingTax,
        sourceLabel: 'RR (school-entered)',
        brackets: [
          ContributionBracket(from: 0, to: 20833),
          ContributionBracket(from: 20833.01, fixedAmount: 0, percentOfExcess: 15),
        ],
      ),
    ],
  );

  Payslip compute({
    Compensation? who,
    Timesheet? sheet,
    ContributionScheme? using,
    double? monthlyBasis,
    bool deductContributions = true,
  }) =>
      computePayslip(
        compensation: who ?? monthly,
        timesheet: sheet ?? fullFortnight(),
        scheme: using ?? scheme,
        monthlyBasisForContributions: monthlyBasis ?? 30000,
        deductContributions: deductContributions,
      );

  group('what somebody earns', () {
    test('a monthly salary is the salary, whatever the month held', () {
      final slip = compute();
      expect(slip.earnings.first.label, 'Basic pay');
      expect(slip.earnings.first.amount, 30000);
    });

    test('a daily rate is the days actually worked', () {
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.daily,
          rate: 900,
        ),
      );
      expect(slip.daysWorked, 10);
      expect(slip.earnings.first.amount, 9000);
      expect(slip.earnings.first.basis, contains('10 days'));
    });

    test('an hourly rate is the hours the scans actually show', () {
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.hourly,
          rate: 400,
        ),
      );
      // Ten days of nine hours.
      expect(slip.earnings.first.amount, 36000);
    });

    test('an allowance is paid but kept out of the basic', () {
      // 13th month and the contribution brackets are reckoned on basic
      // pay, so an allowance folded into it would inflate both.
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.monthly,
          rate: 30000,
          allowance: 2000,
        ),
      );
      expect(slip.basicPay, 30000);
      expect(slip.grossPay, 32000);
    });
  });

  group('a day nobody worked', () {
    Timesheet withAbsences(int count) => buildTimesheet(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          from: from,
          to: to,
          records: [
            for (final d in [1, 2, 3, 4, 5, 8, 9, 10, 11, 12].skip(count)) scan(d),
          ],
          leaves: const [],
        );

    test('comes off a monthly salary at the period day rate', () {
      final slip = compute(sheet: withAbsences(2));
      // Ten working days in the period, so a day is 3,000.
      expect(slip.daysAbsent, 2);
      final absence = slip.deductions.firstWhere((d) => d.label == 'Absences');
      expect(absence.amount, 6000);
      expect(slip.basicPay, 24000);
    });

    test('does not come off when the contract simply pays the month', () {
      // A school that deducts anyway is making a decision this software
      // should not make for it.
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.monthly,
          rate: 30000,
          deductAbsences: false,
        ),
        sheet: withAbsences(2),
      );
      expect(slip.deductions.any((d) => d.label == 'Absences'), isFalse);
      expect(slip.basicPay, 30000);
    });

    test('is never deducted twice from hourly pay', () {
      // The unworked hours were never in the total to begin with.
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.hourly,
          rate: 400,
        ),
        sheet: withAbsences(2),
      );
      expect(slip.deductions.any((d) => d.label == 'Absences'), isFalse);
      expect(slip.basicPay, 400 * 8 * 9);
    });
  });

  group('what the school cannot know', () {
    test('a day scanned in and never out is flagged, not guessed at', () {
      // The honest answer is that this system does not know how long
      // they stayed. Inventing it would put made-up hours on a payslip.
      final slip = compute(
        sheet: fullFortnight(records: [
          for (final d in [1, 2, 3, 4, 5, 8, 9, 10, 11]) scan(d),
          scan(12, outHour: null),
        ]),
      );
      expect(slip.daysMissingTimeOut, 1);
      expect(slip.hoursAreIncomplete, isTrue);
    });

    test('lateness is counted and not deducted', () {
      // The timesheet knows the day was late, not by how much.
      // Deducting a made-up number of minutes is worse than saying so.
      final late = AttendanceRecord(
        id: 'att_late',
        personId: 'emp_1',
        personRole: 'faculty',
        subjectType: AttendanceSubjectType.employee,
        date: '2026-06-01',
        timestampIn: DateTime(2026, 6, 1, 9, 30),
        timestampOut: DateTime(2026, 6, 1, 16, 0),
        status: AttendanceStatus.late,
      );
      final slip = compute(
        sheet: fullFortnight(records: [
          late,
          for (final d in [2, 3, 4, 5, 8, 9, 10, 11, 12]) scan(d),
        ]),
      );
      expect(slip.daysLate, 1);
      expect(slip.deductions.any((d) => d.label.toLowerCase().contains('late')), isFalse);
    });
  });

  group('what comes off', () {
    test('the three agencies, then tax on what is left', () {
      final slip = compute();
      final labels = slip.deductions.map((d) => d.label).toList();
      expect(labels, ['SSS', 'PhilHealth', 'Pag-IBIG', 'Withholding tax']);

      // 30,000 - 1,350 - 750 - 200 = 27,700 taxable.
      // 15% of the excess over 20,833.01 = 1,030.05.
      expect(slip.deductions.last.amount, closeTo(1030.05, 0.01));
    });

    test('tax is computed after the contributions, not before', () {
      // The whole reason they are done in that order. Taxing the gross
      // would take more from everybody, every month.
      final withAgencies = compute();
      final withoutAgencies = compute(
        using: const ContributionScheme(
          confirmedBySchool: true,
          tables: [
            ContributionTable(
              kind: ContributionKind.withholdingTax,
              brackets: [
                ContributionBracket(from: 0, to: 20833),
                ContributionBracket(from: 20833.01, percentOfExcess: 15),
              ],
            ),
          ],
        ),
      );
      final taxed = withAgencies.deductions.last.amount;
      final taxedOnGross = withoutAgencies.deductions.last.amount;
      expect(taxed, lessThan(taxedOnGross));
    });

    test('nothing at all on the first cut-off of a semi-monthly month', () {
      // Deducting the month's contributions on both cut-offs would take
      // double from everybody on semi-monthly pay.
      final slip = compute(deductContributions: false);
      expect(slip.deductions, isEmpty);
      expect(slip.netPay, 30000);
    });

    test('the employer share is carried, though it is not on the payslip', () {
      // It never reaches the employee and it is what the school remits.
      final slip = compute();
      expect(slip.employerContributions, closeTo(2650 + 750 + 200, 0.01));
    });

    test('the deduction lines say where the number came from', () {
      // A deduction an employee cannot trace is one they take on trust.
      final sss = compute().deductions.firstWhere((d) => d.label == 'SSS');
      expect(sss.basis, contains('SSS Circular'));
    });

    test('net pay never goes below zero', () {
      // A table that would take more than somebody earned is a
      // misconfiguration, not a negative payslip.
      final slip = compute(
        who: const Compensation(
          employeeUid: 'emp_1',
          employeeName: 'Maria Santos',
          basis: PayBasis.monthly,
          rate: 500,
        ),
        monthlyBasis: 500,
      );
      expect(slip.netPay, greaterThanOrEqualTo(0));
    });
  });

  group('the contribution tables themselves', () {
    test('an unconfigured agency deducts nothing rather than throwing', () {
      // A half-configured school can still see what the figures would
      // be while they work through it; the payslip refuses elsewhere.
      const empty = ContributionScheme(confirmedBySchool: false);
      expect(contributionOn(empty.tableFor(ContributionKind.sss), 30000).employeeShare, 0);
    });

    test('a salary above every bracket takes the top one', () {
      // Deducting nothing from the highest earner in the school is a
      // worse way to find a stale ceiling than deducting the maximum.
      const table = ContributionTable(
        kind: ContributionKind.sss,
        brackets: [
          ContributionBracket(from: 0, to: 20000, fixedAmount: 900),
          ContributionBracket(from: 20000.01, to: 30000, fixedAmount: 1350),
        ],
      );
      expect(contributionOn(table, 90000).employeeShare, 1350);
    });

    test('a salary below every bracket owes nothing', () {
      const table = ContributionTable(
        kind: ContributionKind.sss,
        brackets: [ContributionBracket(from: 5000, to: 20000, fixedAmount: 900)],
      );
      expect(contributionOn(table, 1000).employeeShare, 0);
    });

    test('a scheme is not usable until it is both complete and confirmed', () {
      const nothing = ContributionScheme();
      expect(nothing.canIssuePayslips, isFalse);
      expect(nothing.unconfiguredKinds.length, 4);

      const typedButUnconfirmed = ContributionScheme(tables: [
        ContributionTable(kind: ContributionKind.sss, brackets: [ContributionBracket(from: 0)]),
        ContributionTable(
            kind: ContributionKind.philHealth, brackets: [ContributionBracket(from: 0)]),
        ContributionTable(
            kind: ContributionKind.pagIbig, brackets: [ContributionBracket(from: 0)]),
        ContributionTable(
            kind: ContributionKind.withholdingTax, brackets: [ContributionBracket(from: 0)]),
      ]);
      expect(typedButUnconfirmed.isComplete, isTrue);
      expect(typedButUnconfirmed.canIssuePayslips, isFalse);
    });
  });

  group('the 13th month', () {
    test('is a twelfth of the basic actually earned', () {
      // PD 851. Not a bonus, not optional, and not on the allowances.
      final year = [for (var i = 0; i < 12; i++) compute()];
      expect(thirteenthMonthPay(year), 30000);
    });

    test('is a twelfth of what a mid-year joiner earned, not of a full year', () {
      final partial = [for (var i = 0; i < 5; i++) compute()];
      expect(thirteenthMonthPay(partial), 12500);
    });

    test('leaves allowances out of it', () {
      final withAllowance = [
        for (var i = 0; i < 12; i++)
          compute(
            who: const Compensation(
              employeeUid: 'emp_1',
              employeeName: 'Maria Santos',
              basis: PayBasis.monthly,
              rate: 30000,
              allowance: 5000,
            ),
          ),
      ];
      expect(thirteenthMonthPay(withAllowance), 30000);
    });
  });
}
