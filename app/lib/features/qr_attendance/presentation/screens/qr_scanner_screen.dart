import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/qr_scan_result.dart';
import '../controllers/qr_attendance_controller.dart';
import '../widgets/attendance_status_badge.dart';

/// Camera-based scanner. Each successful decode is handed to
/// [ScannerController], which debounces rapid-fire detections and calls
/// the markAttendance Cloud Function -- this screen only owns camera UI
/// and the result overlay, no business logic.
class QrScannerScreen extends ConsumerWidget {
  const QrScannerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scannerControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan Attendance QR')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final barcode = capture.barcodes.isNotEmpty ? capture.barcodes.first : null;
              final value = barcode?.rawValue;
              if (value != null) {
                ref.read(scannerControllerProvider.notifier).handleScan(value);
              }
            },
          ),
          _ScanFrameOverlay(),
          if (scanState.isLoading)
            const ColoredBox(
              color: Colors.black45,
              child: Center(child: CircularProgressIndicator()),
            ),
          if (scanState case AsyncData(value: final result?))
            _ResultOverlay(
              result: result,
              onDismiss: () => ref.read(scannerControllerProvider.notifier).reset(),
            ),
          if (scanState case AsyncError(:final error))
            _ErrorOverlay(
              message: error.toString(),
              onDismiss: () => ref.read(scannerControllerProvider.notifier).reset(),
            ),
        ],
      ),
    );
  }
}

class _ScanFrameOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  final QrScanResult result;
  final VoidCallback onDismiss;
  const _ResultOverlay({required this.result, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final actionLabel = switch (result.action) {
      ScanAction.timeIn => 'Time In recorded',
      ScanAction.timeOut => 'Time Out recorded',
      ScanAction.alreadyCompleted => 'Already completed for today',
    };

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(result.personName, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  AttendanceStatusBadge(status: result.status),
                ],
              ),
              const SizedBox(height: 4),
              Text('${result.personRole} · $actionLabel'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onDismiss, child: const Text('Scan Next')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorOverlay({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: onDismiss, child: const Text('Try Again')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
