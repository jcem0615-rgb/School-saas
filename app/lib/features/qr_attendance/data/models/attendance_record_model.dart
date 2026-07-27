import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/attendance_record.dart';

class AttendanceRecordModel extends AttendanceRecord {
  const AttendanceRecordModel({
    required super.id,
    required super.personId,
    required super.personRole,
    required super.subjectType,
    required super.date,
    required super.timestampIn,
    required super.status,
    super.timestampOut,
    super.location,
  });

  factory AttendanceRecordModel.fromFirestore(String id, Map<String, dynamic> data) {
    return AttendanceRecordModel(
      id: id,
      personId: data['personId'] as String,
      personRole: data['personRole'] as String,
      subjectType: AttendanceSubjectType.fromString(data['subjectType'] as String),
      date: data['date'] as String,
      timestampIn: (data['timestampIn'] as Timestamp).toDate(),
      timestampOut: (data['timestampOut'] as Timestamp?)?.toDate(),
      status: AttendanceStatus.fromString(data['status'] as String),
      location: data['location'] as String?,
    );
  }
}
