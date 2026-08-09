import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/answer_key.dart';

class AnswerKeyModel extends AnswerKey {
  const AnswerKeyModel({
    required super.courseworkId,
    required super.answers,
    required super.pointsPerQuestion,
    required super.updatedByName,
    required super.updatedAt,
  });

  factory AnswerKeyModel.fromFirestore(String courseworkId, Map<String, dynamic> data) {
    return AnswerKeyModel(
      courseworkId: courseworkId,
      answers: (data['answers'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      pointsPerQuestion: (data['pointsPerQuestion'] as num?)?.toDouble() ?? 1,
      updatedByName: data['updatedByName'] as String? ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
