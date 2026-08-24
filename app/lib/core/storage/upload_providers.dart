import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import 'upload_repository.dart';
import 'upload_repository_impl.dart';

/// Storage-backed uploader, scoped to the signed-in user so files land
/// under their own school prefix -- which is what storage.rules gates read
/// access on.
///
/// Lives in core rather than a feature because three different features
/// upload: faculty (coursework attachments), students and parents (payment
/// receipts), and registrars (the school's payment QR).
final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('UploadRepository requires a signed-in, school-scoped user.');
  }
  return UploadRepositoryImpl(
    storage: FirebaseStorage.instance,
    schoolId: user.schoolId!,
    uid: user.uid,
  );
});
