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

class CourseworkItem {
  final String id;
  final CourseworkType type;
  final String title;
  final String description;
  final String subject;
  final String section;
  final String teacherId;
  final String teacherName;
  final DateTime? dueDate;
  final double? totalPoints;
  final String? attachmentUrl;
  final bool published;
  final DateTime createdAt;

  const CourseworkItem({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.subject,
    required this.section,
    required this.teacherId,
    required this.teacherName,
    required this.published,
    required this.createdAt,
    this.dueDate,
    this.totalPoints,
    this.attachmentUrl,
  });
}
