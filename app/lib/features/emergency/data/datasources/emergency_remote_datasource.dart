import '../../../../core/location/location_probe.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../models/emergency_alert_model.dart';
import '../models/emergency_contact_model.dart';

class EmergencyRemoteDataSource {
  final FirebaseFirestore _firestore;
  final AppUser _actingUser;

  const EmergencyRemoteDataSource({
    required FirebaseFirestore firestore,
    required AppUser actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  String get _schoolId => _actingUser.schoolId!;

  Stream<List<EmergencyContactModel>> watchContacts() {
    return _firestore
        .collection(FirestorePaths.emergencyContacts(_schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('sortOrder')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => EmergencyContactModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> saveContact({
    String? contactId,
    required String label,
    required String phone,
    String? notes,
    required int sortOrder,
  }) async {
    final collection = _firestore.collection(FirestorePaths.emergencyContacts(_schoolId));
    final ref = contactId == null ? collection.doc() : collection.doc(contactId);
    await ref.set({
      'label': label,
      'phone': phone,
      'notes': notes,
      'sortOrder': sortOrder,
      'schoolId': _schoolId,
      'updatedBy': _actingUser.uid,
      'updatedByName': _actingUser.fullName,
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    }, SetOptions(merge: true));
  }

  Future<void> deleteContact(String contactId) async {
    await _firestore
        .doc('${FirestorePaths.emergencyContacts(_schoolId)}/$contactId')
        .update({'isDeleted': true, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Stream<List<EmergencyAlertModel>> watchAlerts() {
    return _firestore
        .collection(FirestorePaths.emergencyAlerts(_schoolId))
        .orderBy('raisedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => EmergencyAlertModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<EmergencyAlertModel>> watchAlertsForStudent(String studentId) {
    return _firestore
        .collection(FirestorePaths.emergencyAlerts(_schoolId))
        .where('studentId', isEqualTo: studentId)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => EmergencyAlertModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> raiseAlert({
    required String studentId,
    required String studentName,
    required String section,
    String? message,
    LocationResult? location,
  }) async {
    final fix = location?.fix;
    await _firestore.collection(FirestorePaths.emergencyAlerts(_schoolId)).add({
      'studentId': studentId,
      'studentName': studentName,
      'section': section,
      'userId': _actingUser.uid,
      'message': message,
      'schoolId': _schoolId,
      // Server clock. When an alert was raised is the first question
      // anyone asks afterwards.
      'raisedAt': FieldValue.serverTimestamp(),
      // Where they were, or why that is not known. Written as fields on
      // the alert rather than a GeoPoint: staff read these as numbers and
      // hand them to a map URL, and a GeoPoint would need unpacking at
      // every one of those points for no gain.
      if (fix != null) ...{
        'latitude': fix.latitude,
        'longitude': fix.longitude,
        if (fix.accuracyMeters != null) 'locationAccuracyMeters': fix.accuracyMeters,
      },
      if (location?.failure != null) 'locationFailure': location!.failure!.value,
    });
  }

  Future<void> acknowledgeAlert(String alertId) async {
    await _firestore.doc('${FirestorePaths.emergencyAlerts(_schoolId)}/$alertId').update({
      'acknowledgedBy': _actingUser.uid,
      'acknowledgedByName': _actingUser.fullName,
      'acknowledgedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> resolveAlert({required String alertId, String? note}) async {
    await _firestore.doc('${FirestorePaths.emergencyAlerts(_schoolId)}/$alertId').update({
      'resolvedBy': _actingUser.uid,
      'resolvedByName': _actingUser.fullName,
      'resolutionNote': note,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}
