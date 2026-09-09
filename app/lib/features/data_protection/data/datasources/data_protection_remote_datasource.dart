import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';

class DataProtectionRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  DataProtectionRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

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
