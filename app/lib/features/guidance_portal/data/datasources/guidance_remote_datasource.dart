import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../models/guidance_record_model.dart';
import '../models/summons_model.dart';

class ActingGuidance {
  final String uid;
  final String schoolId;
  final String name;
  const ActingGuidance({required this.uid, required this.schoolId, required this.name});
}

class GuidanceRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingGuidance _actingUser;

  const GuidanceRemoteDataSource({required FirebaseFirestore firestore, required ActingGuidance actingUser})
      : _firestore = firestore,
        _actingUser = actingUser;

  Stream<List<GuidanceRecordModel>> watchGuidanceRecords(String studentId) {
    return _firestore
        .collection(FirestorePaths.guidanceRecords(_actingUser.schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('recordedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GuidanceRecordModel.fromFirestore(d.id, d.data())).toList());
  }

  /// Records filed against a section rather than a single student. The
  /// query is separate because Firestore cannot express "studentId is null
  /// OR studentId == X" in one query.
  Stream<List<GuidanceRecordModel>> watchSectionRecords(String section) {
    return _firestore
        .collection(FirestorePaths.guidanceRecords(_actingUser.schoolId))
        .where('section', isEqualTo: section)
        .where('studentId', isNull: true)
        .where('isDeleted', isEqualTo: false)
        .orderBy('recordedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => GuidanceRecordModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createGuidanceRecord({
    String? studentId,
    String? studentName,
    required String section,
    required String category,
    required String notes,
  }) async {
    final ref = _firestore.collection(FirestorePaths.guidanceRecords(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'studentId': studentId,
      'studentName': studentName,
      'section': section,
      'category': category,
      'notes': notes,
      'recordedByName': _actingUser.name,
      'recordedAt': FieldValue.serverTimestamp(),
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  Stream<List<SummonsModel>> watchSummons() {
    return _firestore
        .collection(FirestorePaths.summons(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('scheduledDate', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => SummonsModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createSummons({
    required String studentId,
    required String studentName,
    required String reason,
    required DateTime scheduledDate,
  }) async {
    final ref = _firestore.collection(FirestorePaths.summons(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'studentId': studentId,
      'studentName': studentName,
      'reason': reason,
      'scheduledDate': Timestamp.fromDate(scheduledDate),
      'status': 'pending',
      'issuedByName': _actingUser.name,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  Future<void> updateSummonsStatus({required String summonsId, required String status}) async {
    await _firestore.doc('${FirestorePaths.summons(_actingUser.schoolId)}/$summonsId').update({
      'status': status,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Map<String, dynamic> _editFields() => {
        'updatedBy': _actingUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Both collections set `allow delete: if false`; deletion is a flag
  /// flip and reads already filter on isDeleted.
  Map<String, dynamic> _softDeleteFields() => {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': _actingUser.uid,
        ..._editFields(),
      };

  /// studentId is absent from the payload on purpose -- the guidanceRecords
  /// rule rejects any update that moves a note to a different student.
  Future<void> updateGuidanceRecord({
    required String recordId,
    required String category,
    required String notes,
  }) async {
    await _firestore.doc('${FirestorePaths.guidanceRecords(_actingUser.schoolId)}/$recordId').update({
      'category': category,
      'notes': notes,
      ..._editFields(),
    });
  }

  Future<void> softDeleteGuidanceRecord(String recordId) async {
    await _firestore
        .doc('${FirestorePaths.guidanceRecords(_actingUser.schoolId)}/$recordId')
        .update(_softDeleteFields());
  }

  Future<void> updateSummons({
    required String summonsId,
    required String reason,
    required DateTime scheduledDate,
  }) async {
    await _firestore.doc('${FirestorePaths.summons(_actingUser.schoolId)}/$summonsId').update({
      'reason': reason,
      'scheduledDate': Timestamp.fromDate(scheduledDate),
      ..._editFields(),
    });
  }

  Future<void> softDeleteSummons(String summonsId) async {
    await _firestore
        .doc('${FirestorePaths.summons(_actingUser.schoolId)}/$summonsId')
        .update(_softDeleteFields());
  }
}
