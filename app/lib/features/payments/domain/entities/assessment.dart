import 'fee_structure.dart';

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
    this.sourceStructureId,
    this.sourceStructureName,
    this.remarks,
    this.voidedAt,
    this.voidedByName,
    this.voidReason,
  });

  double get total => items.fold(0, (sum, item) => sum + item.amount);

  double totalFor(FeeCategory category) =>
      items.where((i) => i.category == category).fold(0, (sum, i) => sum + i.amount);

  bool get isVoided => voidedAt != null;

  /// What this assessment currently contributes to the balance. A voided
  /// one contributes nothing, which is what makes the itemised list add
  /// up to the figure on the student's record.
  double get effectiveTotal => isVoided ? 0 : total;

  String get sourceLabel => sourceStructureName ?? 'Ad-hoc charge';
}
