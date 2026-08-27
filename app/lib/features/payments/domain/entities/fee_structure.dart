import '../../../../core/constants/education_level.dart';

/// What a fee is for.
///
/// Three categories, not a free-text field, because these are what a
/// school reports on: tuition is the figure that appears in every
/// enrolment conversation, miscellaneous is the bundle nobody itemises
/// out loud, and other covers what does not belong in either. A fourth
/// would need a reason beyond "somebody might want it".
enum FeeCategory {
  tuition('tuition', 'Tuition'),
  miscellaneous('miscellaneous', 'Miscellaneous'),
  other('other', 'Other');

  final String value;
  final String displayLabel;
  const FeeCategory(this.value, this.displayLabel);

  static FeeCategory fromString(String value) =>
      FeeCategory.values.firstWhere((c) => c.value == value, orElse: () => FeeCategory.other);
}

/// One line on an assessment: what it is called and what it costs.
///
/// A record rather than a document of its own. Fee items have no identity
/// a school ever refers to -- nobody asks "which lab fee row is this" --
/// and keeping them inline means an assessment is one read and one
/// immutable snapshot rather than a join that can drift underneath it.
class FeeItem {
  final String label;
  final double amount;
  final FeeCategory category;

  const FeeItem({
    required this.label,
    required this.amount,
    this.category = FeeCategory.other,
  });

  Map<String, dynamic> toMap() => {
        'label': label,
        'amount': amount,
        'category': category.value,
      };

  factory FeeItem.fromMap(Map<String, dynamic> map) => FeeItem(
        label: map['label'] as String? ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        category: FeeCategory.fromString(map['category'] as String? ?? ''),
      );
}

/// A reusable set of fees, as the school publishes them: "Grade 10,
/// SY 2026-2027".
///
/// This is a template, not a charge. Nothing a student owes changes when
/// one of these is edited -- an assessment copies the items at the moment
/// it is made, so a school that raises tuition in January does not
/// silently reprice every family who enrolled in June. That separation is
/// the whole point of having two collections instead of one.
class FeeStructure {
  final String id;
  final String name;

  /// Which division this applies to.
  final EducationLevel educationLevel;

  /// The grade or year level, or null for "the whole division". A school
  /// with one miscellaneous-fee schedule across all of Junior High wants
  /// one structure, not four identical ones.
  final String? gradeLevel;

  /// The year this schedule belongs to, e.g. "2026-2027". Fees are
  /// re-published every year and last year's are still worth keeping --
  /// a family querying a two-year-old balance is asking about the
  /// schedule that was in force then.
  final String schoolYear;

  final List<FeeItem> items;

  /// Whether this is offered when assessing. Retiring a schedule rather
  /// than deleting it keeps every assessment that cites it readable.
  final bool isActive;

  final DateTime updatedAt;
  final String updatedByName;

  const FeeStructure({
    required this.id,
    required this.name,
    required this.educationLevel,
    required this.schoolYear,
    required this.items,
    required this.updatedAt,
    required this.updatedByName,
    this.gradeLevel,
    this.isActive = true,
  });

  double get total => items.fold(0, (sum, item) => sum + item.amount);

  double totalFor(FeeCategory category) =>
      items.where((i) => i.category == category).fold(0, (sum, i) => sum + i.amount);

  /// "Junior High School · Grade 10" or just "Junior High School".
  String get appliesToLabel {
    final grade = gradeLevel?.trim();
    if (grade == null || grade.isEmpty) return educationLevel.displayLabel;
    return '${educationLevel.displayLabel} · $grade';
  }

  /// Whether this schedule is one a given student could be assessed
  /// under. A structure with no grade level covers its whole division.
  bool appliesTo({required EducationLevel level, required String studentGradeLevel}) {
    if (level != educationLevel) return false;
    final grade = gradeLevel?.trim();
    if (grade == null || grade.isEmpty) return true;
    return grade.toLowerCase() == studentGradeLevel.trim().toLowerCase();
  }
}
