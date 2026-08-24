import 'coursework_item.dart';

/// One student's answer to one piece of gradable coursework.
///
/// Lives in the Faculty feature next to [CourseworkItem] rather than in
/// the Student feature, for the same reason CourseworkItem does: it is
/// one record that both portals look at from opposite ends. A student
/// writes it, a teacher reads it.
///
/// Deliberately *not* a grade. The `grades` collection already exists and
/// is the teacher's assessment; this is the artefact being assessed.
/// Keeping them apart means a resubmission does not silently orphan a
/// mark, and a mark can be corrected without touching what was handed in.
class CourseworkSubmission {
  final String id;
  final String courseworkId;

  /// Denormalized so the teacher's list and the student's history can
  /// name what was answered without a join.
  final String courseworkTitle;

  final String studentId;
  final String studentName;
  final String section;

  /// The auth uid of the student who wrote it. This, not [studentId], is
  /// what firestore.rules anchors ownership on -- a studentId is a record
  /// identifier that anyone could type, while the uid is the one thing
  /// the client cannot lie about.
  final String userId;

  /// The written answer. Either this or [attachmentUrl] must be present:
  /// a submission with neither is somebody tapping Submit by accident,
  /// and recording it as handed in would be worse than not recording it.
  final String answer;

  final String? attachmentUrl;
  final String? attachmentName;

  /// Server-stamped. Never the device clock -- whether work arrived before
  /// a deadline is exactly the thing a client has a motive to shade.
  final DateTime submittedAt;

  /// Set when the student replaces an earlier answer, so a teacher can
  /// see the work was revised rather than silently swapped.
  final DateTime? updatedAt;

  /// One answer per question, in order, for auto-marked coursework.
  /// Empty for free-text work, which is marked by reading it.
  final List<String> answers;

  /// What the marking ran out at, written by the server and never by the
  /// client. A student who could write this field would be writing their
  /// own mark.
  final double? autoScore;
  final int? correctCount;

  /// The teacher's mark. Overrides [autoScore] when set -- automatic
  /// marking is a first pass, not a verdict, and a teacher has to be able
  /// to disagree with it without the disagreement being erased on the
  /// next resubmission.
  final double? score;
  final String? feedback;
  final String? gradedByName;
  final DateTime? gradedAt;

  const CourseworkSubmission({
    required this.id,
    required this.courseworkId,
    required this.courseworkTitle,
    required this.studentId,
    required this.studentName,
    required this.section,
    required this.userId,
    required this.answer,
    required this.submittedAt,
    this.attachmentUrl,
    this.attachmentName,
    this.updatedAt,
    this.answers = const [],
    this.autoScore,
    this.correctCount,
    this.score,
    this.feedback,
    this.gradedByName,
    this.gradedAt,
  });

  /// What to show as the mark: the teacher's if they have given one,
  /// otherwise whatever the automatic pass worked out.
  double? get effectiveScore => score ?? autoScore;

  bool get isGraded => effectiveScore != null;
  bool get wasGradedByTeacher => score != null;

  bool get hasAttachment => attachmentUrl != null && attachmentUrl!.isNotEmpty;
  bool get wasRevised => updatedAt != null;

  /// Whether this arrived after the deadline.
  ///
  /// Derived from the item at read time rather than stored, and that is
  /// the point: a stored flag would be written by the client that had the
  /// motive to get it wrong, and it would also freeze an answer that can
  /// legitimately change when a teacher moves a due date.
  bool isLateFor(CourseworkItem item) {
    final due = item.dueDate;
    if (due == null) return false;
    return submittedAt.isAfter(due);
  }
}

/// Whether a piece of coursework is something a student hands in at all.
///
/// Lesson plans and lessons are material to read; the other four are work
/// to do. That is the same split [CourseworkType.isGradable] already
/// makes, and reusing it means a new coursework type cannot end up
/// gradable but unsubmittable, or the reverse.
extension SubmittableCoursework on CourseworkItem {
  bool get acceptsSubmissions => type.isGradable;
}
