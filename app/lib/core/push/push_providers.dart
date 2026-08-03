import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import 'push_registrar.dart';
import 'push_registrar_impl.dart';

/// Scoped to the signed-in user, because a device token belongs to a
/// person and not to a browser: on a shared school computer the token has
/// to move with whoever is signed in.
///
/// Returns the no-op registrar when nobody is signed in, rather than
/// throwing -- unlike an upload, "register for notifications" is
/// something the app may attempt in the background, and it should go
/// quiet rather than blow up.
final pushRegistrarProvider = Provider<PushRegistrar>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) return const NoOpPushRegistrar();
  return PushRegistrarImpl(
    messaging: FirebaseMessaging.instance,
    firestore: FirebaseFirestore.instance,
    schoolId: user.schoolId!,
    uid: user.uid,
  );
});
