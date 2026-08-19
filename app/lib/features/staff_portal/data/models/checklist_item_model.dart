import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/checklist_item.dart';

class ChecklistItemModel extends ChecklistItem {
  const ChecklistItemModel({
    required super.id,
    required super.task,
    required super.date,
    required super.completed,
    super.completedAt,
    super.notes,
  });

  factory ChecklistItemModel.fromFirestore(String id, Map<String, dynamic> data) {
    return ChecklistItemModel(
      id: id,
      task: data['task'] as String? ?? '',
      date: data['date'] as String? ?? '',
      completed: data['completed'] as bool? ?? false,
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      notes: data['notes'] as String?,
    );
  }
}
