import 'installment.dart';

/// An approved promise to settle by a date.
///
/// A value type rather than the `ApprovalRequest` a promissory note is
/// actually stored as, so the rule below stays arithmetic: it takes two
/// numbers, some dates and a list of covers, and depends on nothing.
/// The adapter that reads approvals into these lives with the caller.
class PromissoryCover {
  /// What the note undertakes to settle.
  final double amount;

  /// The day the promise runs out. A note with no date on it covers
  /// indefinitely, which is what every note written before the field
  /// existed means -- generous, and the honest reading of a record that
  /// simply does not say.
  final DateTime? settleBy;

  /// What to cite on the permit, so a proctor turning somebody away can
  /// be shown the thing that says otherwise.
  final String reference;

  const PromissoryCover({
    required this.amount,
    required this.reference,
    this.settleBy,
  });

  /// Whether the promise still stands on a given day. Inclusive of the
  /// day itself: a note to settle by the 30th covers the exam on the
  /// 30th, which is the whole point of asking for it.
  bool inForceOn(DateTime day) {
    final until = settleBy;
    if (until == null) return true;
    final end = DateTime(until.year, until.month, until.day);
    final asked = DateTime(day.year, day.month, day.day);
    return !asked.isAfter(end);
  }
}

enum ClearanceOutcome {
  /// Nothing is overdue. The ordinary case and the one most students are
  /// in.
  cleared,

  /// Something is overdue, and an approved promissory note covers it.
  clearedByNote,

  /// Something is overdue and nothing covers it.
  blocked;

  bool get isCleared => this != ClearanceOutcome.blocked;
}

/// Whether a student may sit the exam, and why.
class Clearance {
  final ClearanceOutcome outcome;

  /// What was behind before any note was considered.
  final double overdue;

  /// What is still uncovered. Zero unless [outcome] is blocked.
  final double shortfall;

  /// The note being relied on, when one is.
  final PromissoryCover? note;

  const Clearance({
    required this.outcome,
    required this.overdue,
    required this.shortfall,
    this.note,
  });

  bool get isCleared => outcome.isCleared;
}

/// The permit rule.
///
/// A permit to sit an exam is the lever a private school actually uses to
/// collect: the cashier signs a slip, and without it a proctor turns the
/// student away. This decides who gets one.
///
/// Derived, never stored. A permit written down on Monday is a permit
/// that lies on Friday -- the family pays on Wednesday and the record
/// still says they owe. Computing it from the plan and the payments each
/// time means a payment taken at the window clears the student before
/// they have walked back to the classroom.
///
/// Notes are applied oldest-expiry first, so a note that runs out
/// tomorrow is used before one that runs out next month. It makes no
/// difference to whether somebody is cleared today, and it makes the
/// cited note the one that is about to matter.
Clearance clearanceFor({
  required BillingSchedule schedule,
  required double paid,
  required DateTime asOf,
  Iterable<PromissoryCover> notes = const [],
}) {
  final overdue = schedule.overdueAmount(paid: paid, asOf: asOf);
  if (overdue <= 0) {
    return const Clearance(
      outcome: ClearanceOutcome.cleared,
      overdue: 0,
      shortfall: 0,
    );
  }

  final standing = notes.where((n) => n.inForceOn(asOf)).toList()
    ..sort((a, b) {
      final aEnd = a.settleBy;
      final bEnd = b.settleBy;
      if (aEnd == null && bEnd == null) return 0;
      // An open-ended note last: it is the weakest claim to be relying
      // on and the least informative thing to print on a permit.
      if (aEnd == null) return 1;
      if (bEnd == null) return -1;
      return aEnd.compareTo(bEnd);
    });

  final covered = standing.fold<double>(0, (sum, n) => sum + n.amount);
  if (covered + 0.005 >= overdue) {
    return Clearance(
      outcome: ClearanceOutcome.clearedByNote,
      overdue: overdue,
      shortfall: 0,
      note: standing.first,
    );
  }

  // Partly covered is not covered. A note for 5,000 against 8,000
  // overdue leaves 3,000 to settle, and a permit issued on it would be
  // the school agreeing to something nobody agreed to.
  final shortfall = ((overdue - covered) * 100).roundToDouble() / 100;
  return Clearance(
    outcome: ClearanceOutcome.blocked,
    overdue: overdue,
    shortfall: shortfall,
    note: standing.isEmpty ? null : standing.first,
  );
}
