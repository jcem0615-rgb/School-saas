import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// A QR scanner for Windows, where [MobileScanner] does not run.
///
/// mobile_scanner has no Windows implementation at any published version --
/// it wraps MLKit on mobile and BarcodeDetector on the web, and neither
/// exists here. So the desktop build reads the camera itself: `camera`
/// (via camera_windows) for frames, zxing2 -- a pure-Dart port of ZXing --
/// to decode them.
///
/// Frames come from repeated stills rather than a stream. The camera
/// plugin's `startImageStream` is implemented on Android and iOS only, so
/// on Windows the choice is a photo every so often or nothing. A QR code
/// held up to a desk camera is stationary, so the polling interval costs
/// legibility nothing -- it only decides how quickly the scan lands.
class WindowsQrCamera extends StatefulWidget {
  /// Called with the decoded text each time a code is read. The scanner
  /// controller debounces repeats, so this may fire more than once for the
  /// same code held in front of the lens.
  final void Function(String value) onDetect;

  const WindowsQrCamera({super.key, required this.onDetect});

  @override
  State<WindowsQrCamera> createState() => _WindowsQrCameraState();
}

class _WindowsQrCameraState extends State<WindowsQrCamera> {
  /// Slow enough that a decode finishes before the next shot is taken --
  /// capture plus decode is comfortably under this on a desk machine --
  /// and fast enough that holding up a card does not feel ignored.
  static const _interval = Duration(milliseconds: 700);

  CameraController? _camera;
  Timer? _poll;

  /// A capture is in flight. Without this a slow decode would queue shots
  /// behind each other and the preview would stutter as the backlog grew.
  bool _busy = false;

  /// Null while starting up, a message once we know why there is no
  /// preview to show.
  String? _failure;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _failure = 'No camera found on this computer.');
        return;
      }
      // Medium rather than max: a QR code needs enough pixels to resolve
      // its modules, not a photograph. Every extra pixel is paid for twice,
      // in capture time and again in the decode.
      final camera = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
      _poll = Timer.periodic(_interval, (_) => _tick());
    } on CameraException catch (e) {
      // The usual causes are a camera already held by another program and
      // Windows' camera privacy setting. Neither is something the app can
      // fix, so say which it is rather than showing an empty rectangle.
      if (mounted) {
        setState(() => _failure = e.description ?? 'The camera could not be opened.');
      }
    }
  }

  Future<void> _tick() async {
    final camera = _camera;
    if (camera == null || _busy || !camera.value.isInitialized) return;
    _busy = true;
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      // Off the UI isolate: decoding a medium-resolution frame is tens of
      // milliseconds of pure Dart, which is several dropped frames of
      // preview if it runs here.
      final value = await compute(decodeQrFromImageBytes, bytes);
      if (value != null && mounted) widget.onDetect(value);
    } catch (_) {
      // A dropped frame is not worth reporting: the next one is 700ms away.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = _failure;
    if (failure != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined,
                  size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(failure, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Attendance can still be recorded by hand from the '
                'attendance screen.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final camera = _camera;
    if (camera == null) return const Center(child: CircularProgressIndicator());
    return Center(child: CameraPreview(camera));
  }
}

/// Decodes a QR code from an encoded image, or null if there is none.
///
/// Top-level and self-contained so it can be handed to [compute]: an
/// isolate entry point cannot close over anything.
String? decodeQrFromImageBytes(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // decodeImage does not merely return null on input that is not an
    // image -- it hands the bytes to each format's sniffer, and those
    // throw on a truncated header. takePicture produces exactly that if
    // the camera is unplugged mid-capture.
    return null;
  }
  if (decoded == null) return null;

  // A QR code only needs its modules to survive. Downscaling a wide frame
  // first is the difference between a decode that keeps up with the
  // polling interval and one that does not.
  final frame =
      decoded.width > 1000 ? img.copyResize(decoded, width: 1000) : decoded;

  final pixels = Int32List(frame.width * frame.height);
  var i = 0;
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final p = frame.getPixel(x, y);
      pixels[i++] = 0xFF000000 |
          (p.r.toInt() << 16) |
          (p.g.toInt() << 8) |
          p.b.toInt();
    }
  }

  final bitmap = BinaryBitmap(
    HybridBinarizer(RGBLuminanceSource(frame.width, frame.height, pixels)),
  );
  try {
    return QRCodeReader().decode(bitmap).text;
  } on NotFoundException {
    // No code in this frame, which is the normal case for most of them.
    return null;
  } on ReaderException {
    // Something QR-shaped that would not decode -- a blurred or clipped
    // code. Same handling: wait for a better frame.
    return null;
  }
}
