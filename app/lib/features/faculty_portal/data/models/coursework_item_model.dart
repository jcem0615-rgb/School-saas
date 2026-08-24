import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/coursework_item.dart';

class CourseworkItemModel extends CourseworkItem {
  const CourseworkItemModel({
    required super.id,
    required super.type,
    required super.title,
    super.delivery,
    required super.description,
    required super.subject,
    required super.section,
    required super.teacherId,
    required super.teacherName,
    required super.published,
    required super.createdAt,
    super.dueDate,
    super.totalPoints,
    super.attachmentUrl,
    super.attachmentName,
  });

  factory CourseworkItemModel.fromFirestore(String id, Map<String, dynamic> data) {
    return CourseworkItemModel(
      id: id,
      type: CourseworkType.fromString(data['type'] as String),
      // Defaults to face-to-face for items written before the field
      // existed -- see CourseworkDelivery.fromString.
      delivery: CourseworkDelivery.fromString(data['delivery'] as String? ?? ''),
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      subject: data['subject'] as String? ?? '',
      section: data['section'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? '',
      published: data['published'] as bool? ?? true,
      dueDate: (data['dueDate'] as Timestamp?)?.toDate(),
      totalPoints: (data['totalPoints'] as num?)?.toDouble(),
      attachmentUrl: data['attachmentUrl'] as String?,
      attachmentName: data['attachmentName'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
