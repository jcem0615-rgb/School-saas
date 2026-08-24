import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'windows_qr_camera.dart';

/// The camera half of the QR scanner, whichever platform is asking.
///
/// mobile_scanner covers Android, iOS, macOS and the web by wrapping the
/// platform's own barcode detector. It has no Windows implementation, so
/// the desktop build reads the camera and decodes in Dart instead -- see
/// [WindowsQrCamera]. Both hand back the same thing: decoded text.
///
/// The branch is at runtime rather than through a conditional import
/// because neither side needs a library the other lacks. `camera` and
/// zxing2 both compile everywhere; only the plugin registration behind
/// them is Windows-specific.
class QrCamera extends StatelessWidget {
  /// Called with the decoded text of each detection. Repeats are expected
  /// -- a code held in front of the lens reads many times a second -- and
  /// are the scanner controller's problem, not this widget's.
  final void Function(String value) onDetect;

  const QrCamera({super.key, required this.onDetect});

  /// True where mobile_scanner has nothing to run.
  ///
  /// [kIsWeb] is checked first: a browser on a Windows desktop reports
  /// [TargetPlatform.windows], and there mobile_scanner works fine.
  static bool get usesDartDecoder =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  Widget build(BuildContext context) {
    if (usesDartDecoder) return WindowsQrCamera(onDetect: onDetect);

    return MobileScanner(
      onDetect: (capture) {
        final value = capture.barcodes.isNotEmpty
            ? capture.barcodes.first.rawValue
            : null;
        if (value != null) onDetect(value);
      },
    );
  }
}
