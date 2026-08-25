import 'dart:convert';

import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Loads an uploaded image for a printed document -- a school logo, a
/// student's photo, a scanned signature.
///
/// The reason this is not just `networkImage` is the same one that put
/// `openAttachment` in this codebase. An upload is a Storage download URL
/// in a real deployment and a `data:` URI in demo mode, where nothing
/// touches a bucket, and `networkImage` cannot fetch a data URI -- it
/// hands the string to an HTTP client, which fails. The failure is silent
/// by design here (a logo that will not load must never stop a document
/// printing), so what came out was a card and a transcript with the
/// signature line blank and no indication why.
///
/// Every caller wants the same thing: bytes if they can be had, null if
/// they cannot, and never a throw.
Future<pw.MemoryImage?> pdfImage(String url) async {
  if (url.isEmpty) return null;

  if (url.startsWith('data:')) {
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    // `data:<mime>;base64,<payload>` is the only form anything in this
    // app produces; a percent-encoded one is not guessed at.
    if (!url.substring(0, comma).contains(';base64')) return null;
    try {
      return pw.MemoryImage(base64Decode(url.substring(comma + 1)));
    } catch (_) {
      return null;
    }
  }

  try {
    return await networkImage(url) as pw.MemoryImage;
  } catch (_) {
    return null;
  }
}
