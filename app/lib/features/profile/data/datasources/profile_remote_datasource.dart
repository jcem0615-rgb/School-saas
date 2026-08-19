import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';

class ProfileRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  const ProfileRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

  Future<void> updateProfile({String? phone, String? photoUrl}) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': _uid,
    };
    if (phone != null) updates['phone'] = phone;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    await _firestore.doc(FirestorePaths.userDoc(_schoolId, _uid)).update(updates);
  }
}
