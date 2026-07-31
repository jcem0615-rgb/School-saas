import 'dart:typed_data';

import '../../../../core/errors/result.dart';

/// A file attached to a coursework item.
class CourseworkAttachment {
  final String fileName;
  final String url;
  final int sizeBytes;

  const CourseworkAttachment({
    required this.fileName,
    required this.url,
    required this.sizeBytes,
  });
}

/// Uploads coursework attachments.
///
/// Separate from [FacultyRepository] because this is the only place in the
/// app that talks to Storage rather than Firestore, and the two have
/// different failure modes and different security rules (storage.rules
/// caps uploads at 10MB and restricts content types). Keeping it its own
/// port means demo mode can stand in a purely in-memory implementation
/// without faking a Storage SDK.
abstract class AttachmentRepository {
  /// Uploads [bytes] and returns a URL the student portal can read.
  ///
  /// [contentType] is passed through to Storage because storage.rules
  /// matches on it -- an upload without it is rejected.
  Future<Result<CourseworkAttachment>> uploadCourseworkAttachment({
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  });
}
