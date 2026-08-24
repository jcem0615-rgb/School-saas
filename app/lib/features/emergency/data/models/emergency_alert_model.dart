import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/location/location_probe.dart';
import '../../domain/entities/emergency_alert.dart';

class EmergencyAlertModel extends EmergencyAlert {
  const EmergencyAlertModel({
    required super.id,
    required super.studentId,
    required super.studentName,
    required super.section,
    required super.userId,
    required super.raisedAt,
    super.message,
    super.latitude,
    super.longitude,
    super.locationAccuracyMeters,
    super.locationFailure,
    super.acknowledgedByName,
    super.acknowledgedAt,
    super.resolvedAt,
    super.resolutionNote,
  });

  factory EmergencyAlertModel.fromFirestore(String id, Map<String, dynamic> data) {
    return EmergencyAlertModel(
      id: id,
      studentId: data['studentId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      section: data['section'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      message: data['message'] as String?,
      // serverTimestamp() reads back null on the local echo before the
      // round trip; falling back keeps the list from throwing for a frame.
      raisedAt: (data['raisedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      // Firestore hands numbers back as int when they happen to be whole,
      // so these cannot be cast straight to double.
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      locationAccuracyMeters: (data['locationAccuracyMeters'] as num?)?.toDouble(),
      locationFailure: LocationFailure.fromValue(data['locationFailure'] as String?),
      acknowledgedByName: data['acknowledgedByName'] as String?,
      acknowledgedAt: (data['acknowledgedAt'] as Timestamp?)?.toDate(),
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      resolutionNote: data['resolutionNote'] as String?,
    );
  }
}
