import '../../domain/entities/schedule_block.dart';

class ScheduleBlockModel extends ScheduleBlock {
  const ScheduleBlockModel({
    required super.id,
    required super.subject,
    required super.section,
    required super.teacherId,
    required super.teacherName,
    required super.dayOfWeek,
    required super.startMinute,
    required super.endMinute,
    required super.schoolYear,
    super.room,
    super.term,
  });

  factory ScheduleBlockModel.fromFirestore(String id, Map<String, dynamic> data) {
    String? clean(Object? value) {
      final text = (value as String?)?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return ScheduleBlockModel(
      id: id,
      subject: data['subject'] as String? ?? '',
      section: data['section'] as String? ?? '',
      teacherId: data['teacherId'] as String? ?? '',
      teacherName: data['teacherName'] as String? ?? 'Unknown',
      room: clean(data['room']),
      dayOfWeek: (data['dayOfWeek'] as num?)?.toInt() ?? 1,
      startMinute: (data['startMinute'] as num?)?.toInt() ?? 0,
      endMinute: (data['endMinute'] as num?)?.toInt() ?? 0,
      schoolYear: data['schoolYear'] as String? ?? '',
      term: clean(data['term']),
    );
  }
}
