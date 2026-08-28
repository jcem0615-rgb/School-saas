import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/data_request.dart';
import '../models/data_request_model.dart';

class DataProtectionRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;
  final String _userName;

  DataProtectionRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
    required String userName,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid,
        _userName = userName;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(FirestorePaths.dataRequests(_schoolId));

  Stream<List<DataRequestModel>> watchRequests() {
    return _requests
        .orderBy('requestedAt', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DataRequestModel.fromFirestore(d.id, d.data())).toList());
  }

  Stream<List<DataRequestModel>> watchMyRequests(String uid) {
    return _requests
        .where('requestedByUid', isEqualTo: uid)
        .orderBy('requestedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => DataRequestModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<String> raiseRequest({
    required DataRequestKind kind,
    required String details,
    String? studentId,
    String? studentName,
  }) async {
    try {
      final ref = _requests.doc();
      await ref.set({
        'id': ref.id,
        'schoolId': _schoolId,
        'requestedByUid': _uid,
        'requestedByName': _userName,
        'kind': kind.value,
        'details': details,
        'studentId': studentId,
        'studentName': studentName,
        'status': DataRequestStatus.open.value,
        // Written as null rather than omitted: firestore.rules refuses a
        // request that arrives already answered, and a rule cannot check
        // a field that is not there.
        'handledByName': null,
        'handledAt': null,
        'outcome': null,
        'requestedAt': FieldValue.serverTimestamp(),
        'isDeleted': false,
      });
      return ref.id;
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'The request could not be filed.');
    }
  }

  Future<void> closeRequest({
    required String requestId,
    required DataRequestStatus status,
    required String outcome,
  }) async {
    try {
      await _requests.doc(requestId).update({
        'status': status.value,
        'outcome': outcome,
        'handledByName': _userName,
        'handledAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'The request could not be updated.');
    }
  }

  Future<void> acknowledgePrivacyNotice(int version) async {
    try {
      await _firestore.doc(FirestorePaths.userDoc(_schoolId, _uid)).update({
        'privacyNoticeVersion': version,
        'privacyNoticeAcknowledgedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'That could not be recorded.');
    }
  }
}
