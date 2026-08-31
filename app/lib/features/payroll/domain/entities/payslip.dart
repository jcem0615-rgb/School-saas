import '../../../timekeeping/domain/entities/timesheet.dart';
import 'contribution_scheme.dart';

/// How somebody is paid.
enum PayBasis {
  /// A salary for the month, whatever the month contained. What most
  /// full-time teaching staff are on.
  monthly('monthly', 'Monthly salary'),

  /// A rate per day actually worked. Common for substitutes and for
  /// staff on daily engagements.
  daily('daily', 'Daily rate'),

  /// A rate per hour, from the scans. Part-time lecturers.
  hourly('hourly', 'Hourly rate');

  final String value;
  final String displayLabel;
  const PayBasis(this.value, this.displayLabel);

  static PayBasis fromString(String value) => PayBasis.values
      .firstWhere((b) => b.value == value, orElse: () => PayBasis.monthly);
}

/// What one employee is paid, and how.
class Compensation {
  final String employeeUid;
  final String employeeName;
  final PayBasis basis;

  /// Pesos per month, per day or per hour, as [basis] says.
  final double rate;

  /// Allowances paid every period on top of the rate, and not part of
  /// the basic pay that contributions and 13th month are computed from.
  final double allowance;

  /// Whether an unworked day comes off the pay.
  ///
  /// True for most staff. False for the monthly-salaried whose contract
  /// simply pays the month -- and a school that deducts from them anyway
  /// is making a decision this software should not make for it.
  final bool deductAbsences;

  const Compensation({
    required this.employeeUid,
    required this.employeeName,
    required this.basis,
    required this.rate,
    this.allowance = 0,
    this.deductAbsences = true,
  });

  /// A day's pay, for deducting absences and for daily-rate staff.
  ///
  /// The divisor is the school's working days in the period rather than
  /// a fixed 22 or 26, because the period is what was actually worked
  /// and a fixed divisor pays a short February differently from a long
  /// March for no reason anybody can explain to staff.
  double dailyRate(int workingDaysInPeriod) {
    if (basis == PayBasis.daily) return rate;
    if (workingDaysInPeriod <= 0) return 0;
    if (basis == PayBasis.monthly) return _round2(rate / workingDaysInPeriod);
    // Hourly staff have no meaningful day rate; absences are simply
    // hours not worked and never appear.
    return 0;
  }
}

/// One line on a payslip.
class PayslipLine {
  final String label;
  final double amount;

  /// Where the number came from, when it is not obvious -- "SSS Circular
  /// 2025-006", "3 days at 1,363.64". Printed small under the label,
  /// because a deduction an employee cannot trace is one they have to
  /// take on trust.
  final String? basis;

  const PayslipLine({required this.label, required this.amount, this.basis});
}

/// One employee, one period, computed.
class Payslip {
  final String employeeUid;
  final String employeeName;
  final String periodFrom;
  final String periodTo;

  final List<PayslipLine> earnings;
  final List<PayslipLine> deductions;

  /// What contributions and 13th month are reckoned on: the basic pay
  /// for the period, before allowances and after absences.
  final double basicPay;

  final double grossPay;
  final double totalDeductions;
  final double netPay;

  /// The employer's own share, which never appears on the employee's
  /// copy but is what the school actually remits.
  final double employerContributions;

  final int daysWorked;
  final int daysAbsent;
  final int daysLate;

  /// Days somebody scanned in and never out. Carried onto the payslip
  /// because for hourly staff it is the difference between a figure and
  /// a guess.
  final int daysMissingTimeOut;

  const Payslip({
    required this.employeeUid,
    required this.employeeName,
    required this.periodFrom,
    required this.periodTo,
    required this.earnings,
    required this.deductions,
    required this.basicPay,
    required this.grossPay,
    required this.totalDeductions,
    required this.netPay,
    required this.employerContributions,
    required this.daysWorked,
    required this.daysAbsent,
    required this.daysLate,
    required this.daysMissingTimeOut,
  });

  /// Whether the hours behind this payslip are known.
  ///
  /// An hourly employee with an unclosed day has hours this system does
  /// not know, and the honest response is to say so rather than pay them
  /// for the days it can see and quietly drop the rest.
  bool get hoursAreIncomplete => daysMissingTimeOut > 0;
}

/// Computes one payslip.
///
/// Pure, and takes the timesheet rather than fetching one, so every
/// awkward case is a test: a month with no working days, an employee who
/// never scanned out, a salary above the top contribution bracket.
///
/// ## What it does not do
///
/// **Tardiness is reported, not deducted.** The timesheet knows a day
/// was late; it does not know by how long, because that needs the
/// school's own cutoff and the scan together. Deducting a made-up number
/// of minutes from somebody's pay is worse than printing "4 days late"
/// and letting the school decide. The count is on the payslip so the
/// decision has something to sit on.
///
/// **No overtime.** Nothing in this system records authorised overtime,
/// and inferring it from a late scan-out would pay people for staying
/// behind to finish their own marking.
Payslip computePayslip({
  required Compensation compensation,
  required Timesheet timesheet,
  required ContributionScheme scheme,
  /// The full monthly pay this employee is on, which is what the
  /// contribution tables are indexed by -- not the pay for this period.
  /// A semi-monthly payslip still deducts against the monthly bracket.
  required double monthlyBasisForContributions,
  /// True on the second cut-off of the month, when the contributions for
  /// the whole month come off. Deducting the full amount twice would
  /// take double from everybody on semi-monthly pay.
  bool deductContributions = true,
}) {
  final workingDays = timesheet.workingDays;
  final earnings = <PayslipLine>[];
  final deductions = <PayslipLine>[];

  final double basic;
  switch (compensation.basis) {
    case PayBasis.monthly:
      basic = _round2(compensation.rate);
      earnings.add(PayslipLine(
        label: 'Basic pay',
        amount: basic,
        basis: 'Monthly salary',
      ));
    case PayBasis.daily:
      basic = _round2(compensation.rate * timesheet.daysWorked);
      earnings.add(PayslipLine(
        label: 'Basic pay',
        amount: basic,
        basis: '${timesheet.daysWorked} days at ${_peso(compensation.rate)}',
      ));
    case PayBasis.hourly:
      final hours = timesheet.minutesWorked / 60;
      basic = _round2(compensation.rate * hours);
      earnings.add(PayslipLine(
        label: 'Basic pay',
        amount: basic,
        basis: '${hours.toStringAsFixed(2)} hours at ${_peso(compensation.rate)}',
      ));
  }

  // Absences, for the bases where a day not worked is a day not paid.
  // Hourly staff are excluded by construction: their unworked hours were
  // never in the total to begin with, and deducting again would charge
  // them twice for the same absence.
  var absenceDeduction = 0.0;
  if (compensation.deductAbsences &&
      compensation.basis == PayBasis.monthly &&
      timesheet.daysAbsent > 0) {
    final perDay = compensation.dailyRate(workingDays);
    absenceDeduction = _round2(perDay * timesheet.daysAbsent);
    deductions.add(PayslipLine(
      label: 'Absences',
      amount: absenceDeduction,
      basis: '${timesheet.daysAbsent} days at ${_peso(perDay)}',
    ));
  }

  final basicAfterAbsences = _round2(basic - absenceDeduction);

  if (compensation.allowance > 0) {
    earnings.add(PayslipLine(
      label: 'Allowance',
      amount: _round2(compensation.allowance),
      basis: 'Not subject to contributions',
    ));
  }

  final gross = _round2(basicAfterAbsences + compensation.allowance);

  var employerTotal = 0.0;
  if (deductContributions) {
    // The three agencies first: they come off before tax is reckoned,
    // which is what makes them worth doing in this order rather than any
    // other.
    for (final kind in [
      ContributionKind.sss,
      ContributionKind.philHealth,
      ContributionKind.pagIbig,
    ]) {
      final table = scheme.tableFor(kind);
      final amount = contributionOn(table, monthlyBasisForContributions);
      employerTotal += amount.employerShare;
      if (amount.employeeShare > 0) {
        deductions.add(PayslipLine(
          label: kind.displayLabel,
          amount: amount.employeeShare,
          basis: table.sourceLabel,
        ));
      }
    }

    final agencyTotal = deductions
        .where((d) => d.label != 'Absences')
        .fold<double>(0, (sum, d) => sum + d.amount);

    // Tax is on what is left after the mandatory contributions, which is
    // the whole reason they are computed first.
    final taxable = _round2(basicAfterAbsences - agencyTotal);
    final taxTable = scheme.tableFor(ContributionKind.withholdingTax);
    final tax = contributionOn(taxTable, taxable < 0 ? 0 : taxable);
    employerTotal += tax.employerShare;
    if (tax.employeeShare > 0) {
      deductions.add(PayslipLine(
        label: ContributionKind.withholdingTax.displayLabel,
        amount: tax.employeeShare,
        basis: taxTable.sourceLabel,
      ));
    }
  }

  final totalDeductions =
      _round2(deductions.fold<double>(0, (sum, d) => sum + d.amount));

  return Payslip(
    employeeUid: compensation.employeeUid,
    employeeName: compensation.employeeName,
    periodFrom: timesheet.fromDate,
    periodTo: timesheet.toDate,
    earnings: earnings,
    deductions: deductions,
    basicPay: basicAfterAbsences,
    grossPay: gross,
    totalDeductions: totalDeductions,
    // Never below zero. A deduction table that would take more than
    // somebody earned is a misconfiguration, and paying them a negative
    // amount is not a thing that can happen.
    netPay: _round2(gross - totalDeductions < 0 ? 0 : gross - totalDeductions),
    employerContributions: _round2(employerTotal),
    daysWorked: timesheet.daysWorked,
    daysAbsent: timesheet.daysAbsent,
    daysLate: timesheet.daysLate,
    daysMissingTimeOut: timesheet.daysMissingTimeOut,
  );
}

/// The 13th month pay, which is not a bonus and is not optional.
///
/// PD 851: one twelfth of the basic salary earned in the calendar year.
/// Allowances are out of it and so is overtime, which is why [Payslip]
/// keeps basic pay apart from gross rather than only totalling.
///
/// Takes what was actually earned rather than the monthly rate times
/// twelve, because somebody who joined in August is owed a twelfth of
/// what they earned, not a twelfth of a year they were not here for.
double thirteenthMonthPay(Iterable<Payslip> yearsPayslips) {
  final basic = yearsPayslips.fold<double>(0, (sum, p) => sum + p.basicPay);
  return _round2(basic / 12);
}

double _round2(double value) => (value * 100).roundToDouble() / 100;

String _peso(double amount) => amount.toStringAsFixed(2);
