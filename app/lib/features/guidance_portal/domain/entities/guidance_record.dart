enum GuidanceCategory {
  behavioral('behavioral'),
  academic('academic'),
  personal('personal'),
  other('other');

  final String value;
  const GuidanceCategory(this.value);

  static GuidanceCategory fromString(String value) =>
      GuidanceCategory.values.firstWhere((c) => c.value == value);

  String get displayLabel => switch (this) {
        GuidanceCategory.behavioral => 'Behavioral',
        GuidanceCategory.academic => 'Academic',
        GuidanceCategory.personal => 'Personal',
        GuidanceCategory.other => 'Other',
      };
}

/// A confidential counseling note. Deliberately NOT visible to the
/// student or parent it's about, nor to Faculty/Registrar -- restricted
/// to Guidance/Director/Admin only (see firestore.rules). This is a
/// meaningfully different privacy posture than every other per-student
/// record in this system (attendance, grades, payments), which Parents
/// and the student themselves can see -- counseling notes are internal
/// staff records by nature, not shared directly with the family in raw form.
class GuidanceRecord {
  final String id;
  final String studentId;
  final String studentName;
  final GuidanceCategory category;
  final String notes;
  final String recordedByName;
  final DateTime recordedAt;

  const GuidanceRecord({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.category,
    required this.notes,
    required this.recordedByName,
    required this.recordedAt,
  });
}
