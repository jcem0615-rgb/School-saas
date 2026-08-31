import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/grade.dart';
import '../../domain/entities/grading_scheme.dart';

class GradeModel extends Grade {
  const GradeModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.subject,
    required super.section,
    required super.term,
    required super.score,
    required super.maxScore,
    required super.submittedByName,
    required super.submittedAt,
    super.component,
    super.courseworkItemId,
    super.remarks,
  });

  factory GradeModel.fromFirestore(String id, Map<String, dynamic> data) {
    return GradeModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      subject: data['subject'] as String? ?? '',
      section: data['section'] as String? ?? '',
      term: data['term'] as String? ?? '',
      component: GradingComponent.fromString(data['component'] as String? ?? ''),
      courseworkItemId: data['courseworkItemId'] as String?,
      score: (data['score'] as num?)?.toDouble() ?? 0.0,
      maxScore: (data['maxScore'] as num?)?.toDouble() ?? 0.0,
      remarks: data['remarks'] as String?,
      submittedByName: data['submittedByName'] as String? ?? 'Unknown',
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
