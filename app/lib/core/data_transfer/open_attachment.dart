import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a file someone attached — coursework material, a submitted
/// answer, a payment receipt.
///
/// Almost always this is a Storage download URL and the platform browser
/// handles it. The exception is a `data:` URI, which is what
/// DemoUploadRepository produces because demo mode never touches a
/// bucket: `launchUrl` cannot open one. Chrome blocks top-level
/// navigation to `data:` outright, and on Android and iOS there is no
/// handler for it at all. Tapping an attachment in the demo therefore did
/// nothing, which reads as "the file is missing" rather than "this build
/// has no storage".
///
/// So a data: URI is decoded here and handed to the platform's save
/// dialog instead. The file lands in Downloads and opens in whatever the
/// device uses for a PDF, which is where an external launch would have
/// sent it anyway.
Future<void> openAttachment(
  BuildContext context, {
  required String url,
  String? fileName,
}) async {
  final messenger = ScaffoldMessenger.of(context);

  if (url.startsWith('data:')) {
    final bytes = _decodeDataUri(url);
    if (bytes == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('That attachment could not be read.')));
      return;
    }
    final name = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : 'attachment${_extensionFor(url)}';
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      type: FileType.any,
    );
    return;
  }

  final uri = Uri.tryParse(url);
  if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Could not open the attachment.')));
  }
}

/// `data:<mime>;base64,<payload>` — the only form anything in this app
/// produces. A non-base64 data URI returns null rather than being
/// guessed at.
Uint8List? _decodeDataUri(String url) {
  final comma = url.indexOf(',');
  if (comma < 0) return null;
  final header = url.substring(0, comma);
  if (!header.contains(';base64')) return null;
  try {
    return base64Decode(url.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// Guesses a file extension from the data URI's MIME type, so the saved
/// file opens in the right app instead of arriving as an unknown blob.
String _extensionFor(String url) {
  final mime = url.substring(5, url.indexOf(';') == -1 ? 5 : url.indexOf(';'));
  return switch (mime) {
    'application/pdf' => '.pdf',
    'image/png' => '.png',
    'image/jpeg' || 'image/jpg' => '.jpg',
    'image/webp' => '.webp',
    _ => '',
  };
}
