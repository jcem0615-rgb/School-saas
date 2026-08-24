/// Unifies Lesson Plans, Lessons, Assignments, Projects, Exams, and
/// Quizzes into one collection distinguished by [type] -- the same
/// pattern used for Director Portal's generic `approvals` collection.
/// These six content types share the same shape (title, description,
/// subject/section scoping, an optional due date, an optional points
/// value) closely enough that six parallel collections + six near-
/// identical CRUD screens would be pure duplication for no real benefit;
/// a Student/Parent-facing "coursework feed" (built in the Student Portal
/// module) can then filter this one collection by [type] instead of
/// querying six different places.
enum CourseworkType {
  lessonPlan('lesson_plan'),
  lesson('lesson'),
  assignment('assignment'),
  project('project'),
  exam('exam'),
  quiz('quiz');

  final String value;
  const CourseworkType(this.value);

  static CourseworkType fromString(String value) =>
      CourseworkType.values.firstWhere((t) => t.value == value);

  String get displayLabel => switch (this) {
        CourseworkType.lessonPlan => 'Lesson Plan',
        CourseworkType.lesson => 'Lesson',
        CourseworkType.assignment => 'Assignment',
        CourseworkType.project => 'Project',
        CourseworkType.exam => 'Exam',
        CourseworkType.quiz => 'Quiz',
      };

  /// Lesson Plans and Lessons are instructional material (no due date /
  /// points); the other four are gradable work items. Drives which form
  /// fields the create screen shows.
  bool get isGradable => switch (this) {
        CourseworkType.assignment || CourseworkType.project || CourseworkType.exam || CourseworkType.quiz => true,
        CourseworkType.lessonPlan || CourseworkType.lesson => false,
      };
}

/// How the class actually meets this piece of work.
///
/// Face-to-face work is handed out and taken in the room -- the app is
/// just the announcement. Online work has to be self-contained: the
/// student is not in the room, so the material has to travel with the
/// item or there is nothing for them to do. That is why [online] requires
/// an attachment and [faceToFace] does not.
enum CourseworkDelivery {
  faceToFace('face_to_face'),
  online('online');

  final String value;
  const CourseworkDelivery(this.value);

  static CourseworkDelivery fromString(String value) =>
      CourseworkDelivery.values.firstWhere(
        (d) => d.value == value,
        // Everything created before this field existed was handed out in
        // the room, so that is the honest default for an old record.
        orElse: () => CourseworkDelivery.faceToFace,
      );

  String get displayLabel => switch (this) {
        CourseworkDelivery.faceToFace => 'Face-to-face',
        CourseworkDelivery.online => 'Online',
      };

  /// An online item is taken through the app, so it must carry the file
  /// the student works from.
  bool get requiresAttachment => this == CourseworkDelivery.online;
}

class CourseworkItem {
  final String id;
  final CourseworkType type;
  final CourseworkDelivery delivery;
  final String title;
  final String description;
  final String subject;
  final String section;
  final String teacherId;
  final String teacherName;
  final DateTime? dueDate;
  final double? totalPoints;
  final String? attachmentUrl;
  /// Original file name, kept so the UI can show what the file is
  /// without parsing it back out of a signed Storage URL.
  final String? attachmentName;
  final bool published;

  /// How many questions the answer key holds, or 0 when there is no key.
  ///
  /// The *count* is safe to publish to students -- it is how their form
  /// knows to draw six answer boxes -- while the answers themselves live
  /// in a collection students cannot read. Storing the count here rather
  /// than deriving it means the student form never has to touch the key.
  final int questionCount;

  final DateTime createdAt;

  const CourseworkItem({
    required this.id,
    required this.type,
    required this.title,
    this.delivery = CourseworkDelivery.faceToFace,
    required this.description,
    required this.subject,
    required this.section,
    required this.teacherId,
    required this.teacherName,
    required this.published,
    required this.createdAt,
    this.questionCount = 0,
    this.dueDate,
    this.totalPoints,
    this.attachmentUrl,
    this.attachmentName,
  });
}

/// Whether this is marked by comparing answers rather than by reading
/// them. Only true once a teacher has actually supplied a key.
extension AutoMarkable on CourseworkItem {
  bool get isAutoScored => questionCount > 0 && type.isGradable;
}
