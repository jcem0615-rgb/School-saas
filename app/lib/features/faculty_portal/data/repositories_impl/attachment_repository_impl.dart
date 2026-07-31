import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/repositories/attachment_repository.dart';

/// Firebase Storage implementation.
///
/// Objects land under `schools/{schoolId}/coursework/...`, which is what
/// storage.rules scopes access on: reads require the caller's own
/// schoolId claim to match, so a teacher at one school cannot link a file
/// another school's students could open.
class AttachmentRepositoryImpl implements AttachmentRepository {
  final FirebaseStorage _storage;
  final String _schoolId;
  final String _uid;

  const AttachmentRepositoryImpl({
    required FirebaseStorage storage,
    required String schoolId,
    required String uid,
  })  : _storage = storage,
        _schoolId = schoolId,
        _uid = uid;

  @override
  Future<Result<CourseworkAttachment>> uploadCourseworkAttachment({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    // Mirrors the storage.rules cap. Checking here too turns a rejected
    // upload into a clear message instead of a generic permission error
    // after the bytes have already gone over the wire.
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.lengthInBytes > maxBytes) {
      return const Error(ValidationFailure('Attachments are limited to 10MB.'));
    }

    try {
      // Timestamp prefix so two files with the same name don't collide.
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          'schools/$_schoolId/coursework/$_uid/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = _storage.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      final url = await ref.getDownloadURL();
      return Success(CourseworkAttachment(
        fileName: fileName,
        url: url,
        sizeBytes: bytes.lengthInBytes,
      ));
    } on FirebaseException catch (e) {
      return Error(ServerFailure(e.message ?? 'Upload failed.'));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
