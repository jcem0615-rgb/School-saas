import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import 'package:logicclass/features/qr_attendance/presentation/widgets/windows_qr_camera.dart';

/// The Windows scanner decodes QR codes in Dart, because mobile_scanner
/// has no Windows implementation to hand the job to.
///
/// That decoder cannot be exercised by running the app here -- it only
/// takes that path on Windows, and there is no Windows machine and no
/// camera in this test. What can be checked is the part that would
/// actually be wrong: the pixel conversion feeding zxing2. A QR code
/// rendered to an image and read back proves the whole chain end to end,
/// with only the camera replaced.
void main() {
  /// Renders [data] as a QR code PNG, the way a camera would see it: dark
  /// modules on a white field, with a quiet zone. Without the border
  /// zxing2 cannot find the finder patterns and every decode fails.
  Uint8List renderQr(String data, {int scale = 8, int border = 4}) {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qr = QrImage(code);
    final size = (qr.moduleCount + border * 2) * scale;

    final canvas = img.Image(width: size, height: size);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    for (var row = 0; row < qr.moduleCount; row++) {
      for (var col = 0; col < qr.moduleCount; col++) {
        if (!qr.isDark(row, col)) continue;
        img.fillRect(
          canvas,
          x1: (col + border) * scale,
          y1: (row + border) * scale,
          x2: (col + border + 1) * scale - 1,
          y2: (row + border + 1) * scale - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
    return img.encodePng(canvas);
  }

  test('reads back a QR code of the kind the app issues', () {
    // The shape e_id_screen encodes: the QR payload is the student's code,
    // not a URL.
    const payload = 'QR-STU-0001';
    expect(decodeQrFromImageBytes(renderQr(payload)), payload);
  });

  test('survives being scaled down the way a camera frame is', () {
    // Frames wider than 1000px are resized before decoding. A code that
    // only decodes at full size would work in this test and fail against
    // a real webcam, so the large case has to go through that path.
    const payload = 'QR-FAC-0007';
    final large = renderQr(payload, scale: 40);
    final decoded = img.decodePng(large)!;
    expect(decoded.width, greaterThan(1000),
        reason: 'this case is pointless unless it triggers the resize');
    expect(decodeQrFromImageBytes(large), payload);
  });

  test('a frame with no code in it returns null rather than throwing', () {
    // Most frames the scanner takes are this: someone walking up, a hand,
    // an empty desk. The poll loop would stop on an exception.
    final blank = img.Image(width: 320, height: 240);
    img.fill(blank, color: img.ColorRgb8(200, 200, 200));
    expect(decodeQrFromImageBytes(img.encodePng(blank)), isNull);
  });

  test('bytes that are not an image at all return null', () {
    // takePicture can hand back a truncated file if the camera is yanked
    // mid-capture.
    expect(decodeQrFromImageBytes(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
