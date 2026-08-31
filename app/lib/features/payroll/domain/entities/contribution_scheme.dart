/// The four things taken out of a Philippine payslip.
enum ContributionKind {
  sss('sss', 'SSS'),
  philHealth('philhealth', 'PhilHealth'),
  pagIbig('pagibig', 'Pag-IBIG'),
  withholdingTax('withholding_tax', 'Withholding tax');

  final String value;
  final String displayLabel;
  const ContributionKind(this.value, this.displayLabel);

  static ContributionKind fromString(String value) => ContributionKind.values
      .firstWhere((k) => k.value == value, orElse: () => ContributionKind.sss);
}

/// One row of a contribution or tax table.
///
/// One shape for all four, because all four are the same arithmetic
/// underneath: find the bracket the amount falls in, take a fixed sum,
/// and add a percentage of whatever is above the bracket's floor.
///
/// - SSS is fixed amounts per bracket, so [percentOfExcess] is zero.
/// - PhilHealth and Pag-IBIG are percentages, so [fixedAmount] is zero
///   and the floor is zero -- and their ceilings are expressed as the
///   top bracket's own fixed amount.
/// - BIR withholding is "this much, plus this percent of the excess over
///   the bracket floor", which is the shape in full.
class ContributionBracket {
  /// The bracket covers amounts from here up to and including [to].
  final double from;

  /// Null means no ceiling -- the top bracket.
  final double? to;

  /// What the employee pays before the percentage.
  final double fixedAmount;

  /// Percent of the amount above [from] that the employee pays.
  final double percentOfExcess;

  /// The employer's half. Recorded because the school has to remit it
  /// and budget for it, even though it never appears on a payslip.
  final double employerFixedAmount;
  final double employerPercentOfExcess;

  const ContributionBracket({
    required this.from,
    this.to,
    this.fixedAmount = 0,
    this.percentOfExcess = 0,
    this.employerFixedAmount = 0,
    this.employerPercentOfExcess = 0,
  });

  bool covers(double amount) =>
      amount >= from && (to == null || amount <= to!);

  Map<String, dynamic> toMap() => {
        'from': from,
        'to': to,
        'fixedAmount': fixedAmount,
        'percentOfExcess': percentOfExcess,
        'employerFixedAmount': employerFixedAmount,
        'employerPercentOfExcess': employerPercentOfExcess,
      };

  factory ContributionBracket.fromMap(Map<String, dynamic> map) => ContributionBracket(
        from: (map['from'] as num?)?.toDouble() ?? 0,
        to: (map['to'] as num?)?.toDouble(),
        fixedAmount: (map['fixedAmount'] as num?)?.toDouble() ?? 0,
        percentOfExcess: (map['percentOfExcess'] as num?)?.toDouble() ?? 0,
        employerFixedAmount: (map['employerFixedAmount'] as num?)?.toDouble() ?? 0,
        employerPercentOfExcess:
            (map['employerPercentOfExcess'] as num?)?.toDouble() ?? 0,
      );
}

/// One agency's table.
class ContributionTable {
  final ContributionKind kind;
  final List<ContributionBracket> brackets;

  /// What the school calls the circular these came from -- "SSS Circular
  /// 2025-006", "RR 8-2018". Printed beside the deduction so an employee
  /// asking "why is this the amount" has somewhere to look.
  final String? sourceLabel;

  const ContributionTable({
    required this.kind,
    this.brackets = const [],
    this.sourceLabel,
  });

  bool get isEmpty => brackets.isEmpty;

  Map<String, dynamic> toMap() => {
        'kind': kind.value,
        'sourceLabel': sourceLabel,
        'brackets': [for (final b in brackets) b.toMap()],
      };

  factory ContributionTable.fromMap(Map<String, dynamic> map) => ContributionTable(
        kind: ContributionKind.fromString(map['kind'] as String? ?? ''),
        sourceLabel: map['sourceLabel'] as String?,
        brackets: [
          for (final b in (map['brackets'] as List<dynamic>? ?? []))
            if (b is Map<String, dynamic>) ContributionBracket.fromMap(b),
        ],
      );
}

/// What one deduction came to.
class ContributionAmount {
  final ContributionKind kind;
  final double employeeShare;
  final double employerShare;

  const ContributionAmount({
    required this.kind,
    required this.employeeShare,
    required this.employerShare,
  });

  static const none = ContributionAmount(
    kind: ContributionKind.sss,
    employeeShare: 0,
    employerShare: 0,
  );
}

/// A school's whole set of tables.
///
/// ## Why nothing is seeded here
///
/// The grading scheme ships with the DepEd groupings filled in, because
/// those are four coarse numbers that have been stable for a decade, and
/// the risk of shipping them was staleness.
///
/// These are not that. SSS, PhilHealth and Pag-IBIG rates move most
/// years, the withholding table moved with the TRAIN schedule and will
/// move again, and the numbers are fine-grained enough that a wrong one
/// looks entirely plausible on a payslip. The failure is not an
/// out-of-date grade: it is an employee under-deducted all year and
/// handed a bill, or over-deducted and quietly short every payday, and a
/// school remitting the wrong amount to three agencies.
///
/// So this software asserts nothing about what anybody's contribution
/// should be. The tables start **empty**, the school types them in from
/// the circular in front of them, records which circular that was, and
/// confirms. No payslip is issued until they have.
class ContributionScheme {
  final List<ContributionTable> tables;

  /// False until a named person at the school says the tables are right.
  /// The payslip refuses while it is.
  final bool confirmedBySchool;
  final String? confirmedByName;
  final DateTime? confirmedAt;

  const ContributionScheme({
    this.tables = const [],
    this.confirmedBySchool = false,
    this.confirmedByName,
    this.confirmedAt,
  });

  ContributionTable tableFor(ContributionKind kind) => tables.firstWhere(
        (t) => t.kind == kind,
        orElse: () => ContributionTable(kind: kind),
      );

  /// Every table with nothing in it. What the settings screen lists, and
  /// what blocks confirmation.
  List<ContributionKind> get unconfiguredKinds => [
        for (final kind in ContributionKind.values)
          if (tableFor(kind).isEmpty) kind,
      ];

  bool get isComplete => unconfiguredKinds.isEmpty;

  /// Whether a payslip may be issued at all.
  bool get canIssuePayslips => confirmedBySchool && isComplete;
}

/// Reads one deduction out of a table.
///
/// Returns zero for an empty table rather than throwing. An empty table
/// is a school that has not configured that agency yet, and the payslip
/// refuses on [ContributionScheme.canIssuePayslips] rather than here --
/// so a half-configured school can still see what the figures would be
/// while they work through it.
ContributionAmount contributionOn(ContributionTable table, double monthlyPay) {
  if (table.isEmpty) {
    return ContributionAmount(kind: table.kind, employeeShare: 0, employerShare: 0);
  }

  final bracket = table.brackets.where((b) => b.covers(monthlyPay)).firstOrNull ??
      // Above every bracket: the top one applies. A table whose ceiling
      // has not kept up with a salary is a misconfiguration, and
      // deducting nothing from the highest earner in the school is a
      // worse way to discover it than deducting the maximum.
      _topBracket(table.brackets, monthlyPay);

  if (bracket == null) {
    return ContributionAmount(kind: table.kind, employeeShare: 0, employerShare: 0);
  }

  final excess = monthlyPay - bracket.from;
  final overFloor = excess < 0 ? 0.0 : excess;

  return ContributionAmount(
    kind: table.kind,
    employeeShare:
        _round2(bracket.fixedAmount + overFloor * bracket.percentOfExcess / 100),
    employerShare: _round2(
        bracket.employerFixedAmount + overFloor * bracket.employerPercentOfExcess / 100),
  );
}

ContributionBracket? _topBracket(List<ContributionBracket> brackets, double amount) {
  if (brackets.isEmpty) return null;
  final highest = brackets.reduce((a, b) => a.from >= b.from ? a : b);
  // Only when the amount is genuinely above everything. Below the lowest
  // bracket is a different situation -- somebody earning under the
  // table's floor -- and nothing is due there.
  return amount > highest.from ? highest : null;
}

double _round2(double value) => (value * 100).roundToDouble() / 100;
