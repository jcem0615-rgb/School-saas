import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/class_assessment.dart';
import '../../domain/entities/grading_scheme.dart';

class ClassAssessmentModel extends ClassAssessment {
  const ClassAssessmentModel({
    required super.id,
    required super.subject,
    required super.section,
    required super.term,
    required super.title,
    required super.component,
    required super.maxScore,
    required super.createdByName,
    required super.createdAt,
  });

  factory ClassAssessmentModel.fromFirestore(String id, Map<String, dynamic> data) =>
      ClassAssessmentModel(
        id: id,
        subject: data['subject'] as String? ?? '',
        section: data['section'] as String? ?? '',
        term: data['term'] as String? ?? '',
        title: data['title'] as String? ?? 'Untitled',
        component: GradingComponent.fromString(data['component'] as String? ?? ''),
        maxScore: (data['maxScore'] as num?)?.toDouble() ?? 0,
        createdByName: data['createdByName'] as String? ?? 'Unknown',
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

/// The weights a teacher set for one class, or null when they have not.
///
/// Null rather than a default, so the caller decides what "no override"
/// means -- which is the school's confirmed scheme, and saying so in one
/// place beats every screen guessing.
class ClassWeightsModel {
  const ClassWeightsModel._();

  static SubjectWeights? weightsFrom(Map<String, dynamic>? data) {
    if (data == null) return null;
    double? read(String key) {
      final value = (data[key] as num?)?.toDouble();
      return (value == null || !value.isFinite) ? null : value;
    }

    final ww = read('writtenWork');
    final pt = read('performanceTask');
    final qa = read('quarterlyAssessment');
    if (ww == null || pt == null || qa == null) return null;

    return SubjectWeights(
      label: 'Set for this class',
      writtenWork: ww,
      performanceTask: pt,
      quarterlyAssessment: qa,
    );
  }

  static String? setByName(Map<String, dynamic>? data) =>
      data?['setByName'] as String?;
}
