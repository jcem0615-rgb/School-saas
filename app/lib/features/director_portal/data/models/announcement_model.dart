import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/announcement.dart';

class AnnouncementModel extends Announcement {
  const AnnouncementModel({
    required super.id,
    required super.title,
    required super.body,
    required super.audience,
    required super.pinned,
    required super.createdByName,
    required super.createdAt,
  });

  factory AnnouncementModel.fromFirestore(String id, Map<String, dynamic> data) {
    final audienceData = data['audience'] as Map<String, dynamic>? ?? {'all': true, 'roles': []};
    return AnnouncementModel(
      id: id,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      audience: AnnouncementAudience(
        all: audienceData['all'] as bool? ?? true,
        roles: (audienceData['roles'] as List<dynamic>? ?? []).cast<String>(),
      ),
      pinned: data['pinned'] as bool? ?? false,
      createdByName: data['createdByName'] as String? ?? 'Unknown',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
