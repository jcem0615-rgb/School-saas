import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider;
import '../constants/firestore_paths.dart';
import 'device_identity.dart';
import 'session_guard.dart';
import 'session_guard_impl.dart';

/// One per app run. The id it hands out is stable across runs -- see
/// [StoredDeviceIdentity] -- but the object caches it, so this is kept as
/// a single instance rather than rebuilt per read.
final deviceIdentityProvider =
    Provider<DeviceIdentity>((ref) => StoredDeviceIdentity());

/// Scoped to the signed-in account, because a claim is on an account and
/// not on a browser: two people signing in and out on the same school
/// computer each claim their own.
///
/// Returns the no-op guard when nobody is signed in. Demo mode overrides
/// this provider outright (see demo_overrides.dart).
final sessionGuardProvider = Provider<SessionGuard>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const NoOpSessionGuard();

  final schoolId = user.schoolId;
  final profilePath = schoolId != null
      ? FirestorePaths.userDoc(schoolId, user.uid)
      : FirestorePaths.ownerProfileDoc(user.uid);

  return FirestoreSessionGuard(
    firestore: ref.watch(firestoreProvider),
    profilePath: profilePath,
  );
});
