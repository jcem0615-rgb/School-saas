import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';

class TermsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  const TermsRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

  Future<void> acceptTerms(int version) async {
    try {
      await _firestore.doc(FirestorePaths.userDoc(_schoolId, _uid)).update({
        'termsVersion': version,
        // The server's clock, not the device's. "When did they accept?"
        // is the only question this record exists to answer, and a phone
        // with a wrong clock would answer it wrongly.
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'That could not be recorded.');
    }
  }
}
