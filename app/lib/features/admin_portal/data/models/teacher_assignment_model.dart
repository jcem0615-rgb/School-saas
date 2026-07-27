import '../../domain/entities/teacher_assignment.dart';

class TeacherAssignmentModel extends TeacherAssignment {
  const TeacherAssignmentModel({
    required super.id,
    required super.teacherId,
    required super.teacherName,
    required super.subject,
    required super.section,
    required super.schoolYear,
  });

  factory TeacherAssignmentModel.fromFirestore(String id, Map<String, dynamic> data) {
    return TeacherAssignmentModel(
      id: id,
      teacherId: data['teacherId'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
      subject: data['subject'] as String? ?? '',
      section: data['section'] as String? ?? '',
      schoolYear: data['schoolYear'] as String? ?? '',
    );
  }
}
