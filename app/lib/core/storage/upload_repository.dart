import 'dart:typed_data';

import '../errors/result.dart';

/// Where an uploaded file belongs. The value is the folder segment under
/// `schools/{schoolId}/`, which is what storage.rules scopes access on.
enum UploadFolder {
  /// Files a teacher attaches to a coursework item, read by their students.
  coursework('coursework'),

  /// Proof-of-payment images a student or parent submits for review.
  paymentReceipts('payment-receipts'),

  /// The school's own e-wallet QR, shown to anyone paying online.
  paymentSettings('payment-settings'),

  /// The school logo, shown in the app and on printed IDs.
  branding('branding');

  final String folder;
  const UploadFolder(this.folder);
}

class UploadedFile {
  final String fileName;
  final String url;
  final int sizeBytes;

  const UploadedFile({
    required this.fileName,
    required this.url,
    required this.sizeBytes,
  });
}

/// Uploads a file and returns a URL others can read.
///
/// This is the only port in the app that talks to Storage rather than
/// Firestore, which is why it is its own thing: different failure modes,
/// different rules (storage.rules caps size and content type), and a demo
/// implementation that needs no bucket at all.
///
/// It started life as a coursework-only port. Payment receipts and the
/// school's payment QR need exactly the same upload, so the destination is
/// a parameter rather than baked into the method name.
abstract class UploadRepository {
  Future<Result<UploadedFile>> upload({
    required UploadFolder folder,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  });
}
