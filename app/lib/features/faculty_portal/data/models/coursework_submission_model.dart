import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/coursework_submission.dart';

class CourseworkSubmissionModel extends CourseworkSubmission {
  const CourseworkSubmissionModel({
    required super.id,
    required super.courseworkId,
    required super.courseworkTitle,
    required super.studentId,
    required super.studentName,
    required super.section,
    required super.userId,
    required super.answer,
    required super.submittedAt,
    super.attachmentUrl,
    super.attachmentName,
    super.updatedAt,
    super.answers,
    super.autoScore,
    super.correctCount,
    super.score,
    super.feedback,
    super.gradedByName,
    super.gradedAt,
  });

  factory CourseworkSubmissionModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CourseworkSubmissionModel(
      id: id,
      courseworkId: data['courseworkId'] as String? ?? '',
      courseworkTitle: data['courseworkTitle'] as String? ?? '',
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      section: data['section'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      answer: data['answer'] as String? ?? '',
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentName: data['attachmentName'] as String?,
      // A serverTimestamp() write reads back null on the local echo
      // before the server round-trips. Falling back to "now" keeps the
      // list from throwing during that one frame; the real value lands a
      // moment later.
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      answers: (data['answers'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      // Written only by onCourseworkSubmissionWritten; firestore.rules
      // rejects any client that tries to set these.
      autoScore: (data['autoScore'] as num?)?.toDouble(),
      correctCount: (data['correctCount'] as num?)?.toInt(),
      score: (data['score'] as num?)?.toDouble(),
      feedback: data['feedback'] as String?,
      gradedByName: data['gradedByName'] as String?,
      gradedAt: (data['gradedAt'] as Timestamp?)?.toDate(),
    );
  }
}
