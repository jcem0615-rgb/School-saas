import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../errors/failures.dart';
import '../errors/result.dart';
import 'upload_repository.dart';

/// Firebase Storage implementation.
///
/// Objects land under `schools/{schoolId}/{folder}/{uid}/`, the prefix
/// storage.rules scopes reads on, so one school can never link a file
/// another school's users could open.
class UploadRepositoryImpl implements UploadRepository {
  final FirebaseStorage _storage;
  final String _schoolId;
  final String _uid;

  const UploadRepositoryImpl({
    required FirebaseStorage storage,
    required String schoolId,
    required String uid,
  })  : _storage = storage,
        _schoolId = schoolId,
        _uid = uid;

  /// Mirrors the ceiling in storage.rules. Checking it here too turns an
  /// oversized file into a clear message instead of a generic permission
  /// error after the bytes have already gone over the wire.
  static const maxBytes = 10 * 1024 * 1024;

  @override
  Future<Result<UploadedFile>> upload({
    required UploadFolder folder,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (bytes.lengthInBytes > maxBytes) {
      return const Error(ValidationFailure('Files are limited to 10MB.'));
    }

    try {
      // Timestamp prefix so two files with the same name cannot collide.
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = 'schools/$_schoolId/${folder.folder}/$_uid/'
          '${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = _storage.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      return Success(UploadedFile(
        fileName: fileName,
        url: await ref.getDownloadURL(),
        sizeBytes: bytes.lengthInBytes,
      ));
    } on FirebaseException catch (e) {
      return Error(ServerFailure(e.message ?? 'Upload failed.'));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
