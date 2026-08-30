import '../../../../core/constants/education_level.dart';

/// How the school stands right now: how many students it is teaching, how
/// much of what it has charged is still owed, and how much has come in
/// this month.
///
/// The Owner has had these numbers since the beginning, because billing
/// runs on the active-student count. The school itself had nowhere to see
/// them -- a Director could open a report and read the same figures, but
/// only by going and asking for one, which is not the same as knowing.
///
/// Money is nullable rather than zero, and the distinction carries
/// meaning: null is "this reader may not see it", zero is "there is none".
/// A Principal is division-level academic oversight and deliberately
/// cannot read payments (docs/16-principal-role.md) -- the same boundary
/// already drawn for expenses -- so their card shows the head count and
/// stops.
class SchoolTotals {
  /// Students whose status is `enrolled`. Not every record: a graduated
  /// or transferred-out student is still on file and is not somebody the
  /// school is teaching or billing for.
  final int activeStudents;

  /// Set when these figures cover one division only, because the reader
  /// is scoped to it. The card says so; a head count that silently
  /// omitted three quarters of the school would be worse than no count.
  final EducationLevel? division;

  /// The sum of every positive balance, as it stands now.
  ///
  /// Positive only. A credit balance is money the school is holding, not
  /// money it is owed, and netting the two would let one family's
  /// overpayment quietly cancel another family's arrears -- the same
  /// reasoning the collections report already applies.
  final double? outstanding;

  /// How many students carry one of those balances. The figure a
  /// registrar acts on: one family owing 200,000 and two hundred owing a
  /// thousand each are the same total and a completely different morning.
  final int? studentsOwing;

  /// Payments received since the first of the month, refunds netted off.
  final double? collectedThisMonth;

  const SchoolTotals({
    required this.activeStudents,
    this.division,
    this.outstanding,
    this.studentsOwing,
    this.collectedThisMonth,
  });

  /// Whether this reader is allowed the money half of the card.
  bool get includesMoney => outstanding != null;

  /// Nothing to show yet, rather than a school with no students -- used
  /// while the first read is in flight.
  static const empty = SchoolTotals(activeStudents: 0);
}
