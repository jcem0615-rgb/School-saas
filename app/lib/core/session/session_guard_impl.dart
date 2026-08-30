import 'package:cloud_firestore/cloud_firestore.dart';

import 'session_guard.dart';

/// Firestore-backed guard. One document per account, deterministic id.
///
/// `current` rather than a generated id, and a document rather than a
/// collection of them, because the question this answers is "which single
/// device holds this account" -- a collection would invite a second row
/// and a second row is the thing being ruled out. A device that claims
/// the account overwrites the one field that matters.
class FirestoreSessionGuard implements SessionGuard {
  static const _docId = 'current';

  final FirebaseFirestore _firestore;

  /// The account's own profile path: `schools/{id}/users/{uid}` for
  /// everyone in a school, `platform_owner_profiles/{uid}` for the Owner,
  /// who belongs to no school.
  final String _profilePath;

  const FirestoreSessionGuard({
    required FirebaseFirestore firestore,
    required String profilePath,
  })  : _firestore = firestore,
        _profilePath = profilePath;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.doc('$_profilePath/sessions/$_docId');

  @override
  Future<void> claim(DeviceClaim claim) async {
    await _doc.set({
      'deviceId': claim.deviceId,
      'deviceLabel': claim.deviceLabel,
      'claimedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<DeviceClaim?> watch() {
    // includeMetadataChanges is left off: a local write echoes back
    // immediately from cache with the same deviceId this device just
    // wrote, which is a `hold` either way. What has to arrive from the
    // server is somebody *else's* claim, and that arrives on the ordinary
    // stream.
    return _doc.snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return null;
      final deviceId = data['deviceId'];
      // A document with no device id claims nothing. Treating a
      // malformed one as a claim by an unknown device would sign
      // everybody out and leave nobody able to sign back in.
      if (deviceId is! String || deviceId.isEmpty) return null;
      return DeviceClaim(
        deviceId: deviceId,
        deviceLabel: data['deviceLabel'] as String? ?? 'another device',
        claimedAt: (data['claimedAt'] as Timestamp?)?.toDate(),
      );
    });
  }
}
