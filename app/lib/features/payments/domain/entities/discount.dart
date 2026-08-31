import 'fee_structure.dart';

/// Why a family is paying less than the published fees.
///
/// A closed list rather than free text, and that is the whole point of
/// this feature. A waiver typed into a remarks box cannot be reported on,
/// and "how much did we give away in discounts this year" is a question a
/// private school's board asks every single year. Before this, the only
/// trace of a scholarship in the system was the hint text on the assess
/// screen suggesting somebody type one.
///
/// The list is what Philippine private schools actually grant. A seventh
/// would need a reason beyond "somebody might want it" -- [other] carries
/// the long tail, and its label is required, so it still says what it was.
enum DiscountKind {
  sibling('sibling', 'Sibling discount'),
  earlyBird('early_bird', 'Early payment'),
  employeeChild('employee_child', "Employee's child"),
  alumni('alumni', 'Alumni'),
  academic('academic', 'Academic scholarship'),
  financialAid('financial_aid', 'Financial assistance'),
  other('other', 'Other');

  final String value;
  final String displayLabel;
  const DiscountKind(this.value, this.displayLabel);

  static DiscountKind fromString(String value) => DiscountKind.values
      .firstWhere((k) => k.value == value, orElse: () => DiscountKind.other);
}

/// One reduction on one assessment.
///
/// Inline on the assessment, like the fee items, and copied rather than
/// referenced for the same reason: a school that changes its sibling
/// policy in January must not silently rewrite what a family was granted
/// in June.
///
/// The *amount* is stored even when a percentage produced it. A stored
/// percentage alone would have to be recomputed against fees that can be
/// edited afterwards, so a 10% discount granted on 20,000 could quietly
/// become a discount on 24,000 -- and the printed assessment a family is
/// holding would stop matching the system. The percentage is kept beside
/// it so the line can still read "Sibling discount (10%)", which is what
/// makes it checkable.
class Discount {
  final DiscountKind kind;

  /// What to call it on the assessment a family is handed. Defaults to
  /// the kind's own label, but a school granting "Faculty child - 50%,
  /// board resolution 2026-04" wants its own words.
  final String label;

  /// The money taken off. Always positive; it is subtracted, never added.
  final double amount;

  /// The rate that produced [amount], if one did. Null for a flat
  /// dicount typed as a peso figure.
  final double? percentage;

  /// Which fees the percentage was taken against. Null means the whole
  /// assessment.
  ///
  /// Not decoration: most PH private schools discount tuition and not
  /// the miscellaneous fees, because the miscellaneous bundle is largely
  /// money passed through to third parties. A 10% discount that quietly
  /// included the laboratory fee is a school giving away more than it
  /// decided to.
  final FeeCategory? appliesTo;

  /// Who authorised it. A discount is a decision, and a decision with no
  /// name against it is one nobody can be asked about.
  final String approvedByName;

  const Discount({
    required this.kind,
    required this.label,
    required this.amount,
    required this.approvedByName,
    this.percentage,
    this.appliesTo,
  });

  /// "Sibling discount (10% of tuition)" -- the line as it prints.
  String get displayLine {
    if (percentage == null) return label;
    final rate = percentage!;
    // Trailing zeros stripped: a school grants 10%, 12.5% or 33.33%, and
    // "12.50%" on a printed assessment reads as a rate somebody fussed
    // over rather than the one they were told.
    final rounded = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    final base = appliesTo == null ? '' : ' of ${appliesTo!.displayLabel.toLowerCase()}';
    return '$label ($rounded%$base)';
  }

  Map<String, dynamic> toMap() => {
        'kind': kind.value,
        'label': label,
        'amount': amount,
        'percentage': percentage,
        'appliesTo': appliesTo?.value,
        'approvedByName': approvedByName,
      };

  factory Discount.fromMap(Map<String, dynamic> map) => Discount(
        kind: DiscountKind.fromString(map['kind'] as String? ?? ''),
        label: map['label'] as String? ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        percentage: (map['percentage'] as num?)?.toDouble(),
        appliesTo: map['appliesTo'] == null
            ? null
            : FeeCategory.fromString(map['appliesTo'] as String),
        approvedByName: map['approvedByName'] as String? ?? 'Unknown',
      );
}

/// What a percentage comes to, against the fees it applies to.
///
/// Shared by the editor, the use case and the server, so the figure a
/// registrar is shown before granting is the figure that gets stored.
/// Three copies of this rounding would eventually disagree by a centavo,
/// and a centavo of disagreement on a printed assessment is a phone call.
double discountAmountFor({
  required List<FeeItem> items,
  required double percentage,
  FeeCategory? appliesTo,
}) {
  final base = appliesTo == null
      ? items.fold<double>(0, (sum, i) => sum + i.amount)
      : items
          .where((i) => i.category == appliesTo)
          .fold<double>(0, (sum, i) => sum + i.amount);
  return ((base * percentage / 100) * 100).roundToDouble() / 100;
}

/// Everything taken off, as one figure.
double totalDiscount(Iterable<Discount> discounts) {
  final sum = discounts.fold<double>(0, (running, d) => running + d.amount);
  return (sum * 100).roundToDouble() / 100;
}
