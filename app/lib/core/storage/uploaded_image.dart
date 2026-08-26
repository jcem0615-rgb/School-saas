import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows an image someone uploaded -- a school logo, an ID photo, a
/// scanned signature.
///
/// The screen-side twin of [pdfImage], and it exists for the same reason.
/// An upload is a Storage download URL in a real deployment and a `data:`
/// URI in demo mode, where nothing touches a bucket. `Image.network`
/// handles both on the web, because there it becomes an `<img src>` and
/// the browser decodes the data URI itself -- but on Android, iOS and
/// Windows it goes through an HTTP client, which cannot fetch a `data:`
/// URI at all. So an uploaded logo that looked fine in the browser demo
/// was simply absent in the APK and the desktop build, and silently: the
/// error builder swallows it, because a logo that will not load must
/// never break the screen it sits on.
///
/// Decoding the URI here makes the two behave the same everywhere.
class UploadedImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown when the bytes cannot be had. Defaults to nothing, which is
  /// what a decorative image should degrade to.
  final Widget? fallback;

  const UploadedImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final blank = fallback ?? const SizedBox.shrink();
    if (url.isEmpty) return blank;

    if (url.startsWith('data:')) {
      final bytes = _decode(url);
      if (bytes == null) return blank;
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => blank,
      );
    }

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => blank,
    );
  }

  /// `data:<mime>;base64,<payload>` -- the only form anything in this app
  /// produces. A percent-encoded one is not guessed at.
  static Uint8List? _decode(String url) {
    final comma = url.indexOf(',');
    if (comma < 0) return null;
    if (!url.substring(0, comma).contains(';base64')) return null;
    try {
      return base64Decode(url.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }
}
