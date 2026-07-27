import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/meeting.dart';

class MeetingModel extends Meeting {
  const MeetingModel({
    required super.id,
    required super.title,
    required super.startTime,
    required super.endTime,
    required super.attendeeRoles,
    required super.status,
    required super.createdByName,
    super.description,
    super.location,
  });

  factory MeetingModel.fromFirestore(String id, Map<String, dynamic> data) {
    return MeetingModel(
      id: id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      location: data['location'] as String?,
      attendeeRoles: (data['attendeeRoles'] as List<dynamic>? ?? []).cast<String>(),
      status: MeetingStatus.fromString(data['status'] as String? ?? 'scheduled'),
      createdByName: data['createdByName'] as String? ?? 'Unknown',
    );
  }
}
