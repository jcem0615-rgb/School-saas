import 'discount.dart';
import 'fee_structure.dart';
import 'installment.dart';

/// One occasion on which fees were charged to one student.
///
/// This is what turns a balance from a number into an answer. Before it
/// existed, a family asking "why do we owe 24,000?" got the figure and
/// nothing else, because the only things that had ever written to
/// `balance` were payments (which subtract) and a registrar typing a
/// total by hand (which explains nothing). An assessment records what was
/// charged, itemised, at the moment it was charged.
///
/// The items are copied from the fee structure rather than referenced.
/// A structure is a template the school edits between years; an
/// assessment is a thing that happened to a family. Pointing at the
/// template would mean that raising tuition in January silently changed
/// what June's families are recorded as having been charged.
class Assessment {
  final String id;
  final String studentId;

  /// Denormalised for the same reason the release log denormalises it:
  /// a record of what happened should not be rewritten by a later
  /// correction to the student's name.
  final String studentName;

  final String schoolYear;

  /// The structure this came from, if any. Null for an ad-hoc charge --
  /// a replacement ID, a make-up exam fee -- which is a real thing a
  /// registrar does and should not require inventing a schedule for.
  final String? sourceStructureId;
  final String? sourceStructureName;

  final List<FeeItem> items;

  /// The payment plan as it stood when this was charged, copied in for
  /// exactly the reason the items are: a school that moves next year's
  /// due dates must not silently move the dates a family already agreed
  /// to and budgeted around.
  ///
  /// Empty means the whole amount fell due immediately, which is both
  /// the honest reading of an ad-hoc charge and what every assessment
  /// written before this field existed meant.
  final List<Installment> installments;

  /// What was taken off the published fees, and why.
  ///
  /// Copied in like everything else here: a school that changes its
  /// sibling policy in January must not rewrite what a family was
  /// granted in June.
  final List<Discount> discounts;

  final String assessedByName;
  final DateTime assessedAt;
  final String? remarks;

  /// When this was reversed, and why. An assessment is never deleted --
  /// the balance moved when it was made, and a record that can vanish
  /// leaves a balance nobody can account for. Voiding reverses the
  /// balance and leaves both facts on the record.
  final DateTime? voidedAt;
  final String? voidedByName;
  final String? voidReason;

  const Assessment({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.schoolYear,
    required this.items,
    required this.assessedByName,
    required this.assessedAt,
    this.installments = const [],
    this.discounts = const [],
    this.sourceStructureId,
    this.sourceStructureName,
    this.remarks,
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
  });

  /// The published fees, before anything was taken off. What the school
  /// charges everybody.
  double get grossTotal => items.fold(0, (sum, item) => sum + item.amount);

  double get discountTotal => totalDiscount(discounts);

  /// What this family was actually charged, and what moved the balance.
  ///
  /// `total` nets the discounts rather than a separate `netTotal` sitting
  /// beside a gross `total`, deliberately: every existing caller -- the
  /// balance, the breakdown, the collections report -- means "what does
  /// this family owe for this", and every one of them would have been
  /// wrong by the discount if the netting had been opt-in. An assessment
  /// with no discounts is unchanged, which is every assessment written
  /// before this existed.
  ///
  /// Never below zero. A discount larger than the fees is refused when it
  /// is granted; clamping here as well means a hand-edited document
  /// cannot produce a charge that pays a family to enrol.
  double get total {
    final net = grossTotal - discountTotal;
    return net < 0 ? 0 : (net * 100).roundToDouble() / 100;
  }

  double totalFor(FeeCategory category) =>
      items.where((i) => i.category == category).fold(0, (sum, i) => sum + i.amount);

  bool get isVoided => voidedAt != null;

  /// What this assessment currently contributes to the balance. A voided
  /// one contributes nothing, which is what makes the itemised list add
  /// up to the figure on the student's record.
  double get effectiveTotal => isVoided ? 0 : total;

  String get sourceLabel => sourceStructureName ?? 'Ad-hoc charge';

  /// A voided assessment has no plan. It charged nothing in the end, so
  /// chasing a family for its instalments would be chasing them for
  /// money the school itself took back.
  BillingSchedule get schedule =>
      isVoided ? BillingSchedule.empty : BillingSchedule(installments);

  bool get hasSchedule => !isVoided && installments.isNotEmpty;

  /// Every plan a student is under, as one schedule.
  ///
  /// A family is not on one plan. They are on the tuition plan, plus
  /// whatever the make-up exam fee charged in November, and what they
  /// owe today is the sum of both. Merging the lines rather than
  /// reporting per assessment is what makes a single "you are ₱4,500
  /// behind" possible, and it is correct for the same reason the
  /// arithmetic is: payments are not earmarked to an assessment either.
  ///
  /// Assessments with no plan contribute a single line falling due the
  /// day they were charged. That is what "due immediately" means, and
  /// leaving them out instead would quietly excuse an ad-hoc charge from
  /// ever being overdue.
  static BillingSchedule combinedSchedule(Iterable<Assessment> assessments) {
    final lines = <Installment>[];
    for (final assessment in assessments) {
      if (assessment.isVoided) continue;
      if (assessment.installments.isEmpty) {
        if (assessment.total <= 0) continue;
        lines.add(Installment(
          label: assessment.sourceLabel,
          dueDate: assessment.assessedAt,
          amount: assessment.total,
        ));
        continue;
      }
      lines.addAll(assessment.installments);
    }
    return BillingSchedule(lines);
  }
}
