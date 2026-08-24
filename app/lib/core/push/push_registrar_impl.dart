import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_registrar.dart';

/// FCM-backed registrar. Web push needs a VAPID key, which is per-project
/// and public (it identifies the project to the browser's push service --
/// it is not a secret, and it is not enough to send anything).
///
/// Pass it at build time so a fork of this repo deploys to its own
/// project without editing source:
///
///   flutter build web --release --dart-define=VAPID_KEY=BN...
const _vapidKey = String.fromEnvironment('VAPID_KEY');

class PushRegistrarImpl implements PushRegistrar {
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;

  PushRegistrarImpl({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
  })  : _messaging = messaging,
        _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid;

  CollectionReference<Map<String, dynamic>> get _tokens =>
      _firestore.collection('schools/$_schoolId/users/$_uid/deviceTokens');

  @override
  Future<bool> register() async {
    try {
      final settings = await _messaging.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }

      final token = await _currentToken();
      if (token == null) return false;

      // Keyed by the token, so re-registering the same browser overwrites
      // rather than adding a row per launch.
      await _tokens.doc(token).set({
        'token': token,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      // Declined permission, an unsupported browser, a blocked service
      // worker: all the same to the caller. Nobody opening this app to
      // check a grade should be shown a crash because push is
      // unavailable.
      return false;
    }
  }

  @override
  Future<void> unregister() async {
    try {
      final token = await _currentToken();
      if (token != null) await _tokens.doc(token).delete();
      // Drops the token at the FCM end too, so a shared school computer
      // stops receiving for the account that just signed out.
      await _messaging.deleteToken();
    } catch (_) {
      // Sign-out must not fail because a token could not be cleaned up.
    }
  }

  @override
  Future<bool> isRegistered() async {
    try {
      final token = await _currentToken();
      if (token == null) return false;
      final doc = await _tokens.doc(token).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Web needs the VAPID key; the mobile SDKs supply their own and reject
  /// the argument, hence the split.
  Future<String?> _currentToken() =>
      kIsWeb && _vapidKey.isNotEmpty ? _messaging.getToken(vapidKey: _vapidKey) : _messaging.getToken();
}
