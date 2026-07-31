import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/qr_attendance_remote_datasource.dart';
import '../../data/repositories_impl/qr_attendance_repository_impl.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/qr_scan_result.dart';
import '../../domain/repositories/qr_attendance_repository.dart';
import '../../domain/usecases/scan_qr_usecase.dart';
import '../../domain/usecases/watch_attendance_history_usecase.dart';

final qrAttendanceRemoteDataSourceProvider = Provider<QrAttendanceRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('QrAttendanceRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return QrAttendanceRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    schoolId: user.schoolId!,
  );
});

final qrAttendanceRepositoryProvider = Provider<QrAttendanceRepository>((ref) {
  return QrAttendanceRepositoryImpl(ref.watch(qrAttendanceRemoteDataSourceProvider));
});

/// Family-keyed so a single scanner screen and a parent viewing two
/// children's history can each hold independent, correctly-scoped streams.
final attendanceHistoryStreamProvider =
    StreamProvider.autoDispose.family<List<AttendanceRecord>, String>((ref, personId) {
  return WatchAttendanceHistoryUseCase(ref.watch(qrAttendanceRepositoryProvider))(personId);
});

/// Drives the scanner screen: one scan in flight at a time, with the last
/// result surfaced so the UI can show a confirmation overlay before the
/// camera resumes scanning.
class ScannerController extends StateNotifier<AsyncValue<QrScanResult?>> {
  final ScanQrUseCase _scanQr;
  ScannerController(this._scanQr) : super(const AsyncData(null));

  bool _busy = false;

  Future<void> handleScan(String qrToken) async {
    // mobile_scanner fires onDetect repeatedly while a code is in frame;
    // without this guard the same code would trigger dozens of duplicate
    // calls per second.
    if (_busy) return;
    _busy = true;
    if (mounted) state = const AsyncLoading();
    final result = await _scanQr(qrToken: qrToken);
    if (mounted) state = switch (result) {
      Success(:final value) => AsyncData(value),
      Error(:final failure) => AsyncError(failure.message, StackTrace.current),
    };
    _busy = false;
  }

  void reset() => state = const AsyncData(null);
}

final scannerControllerProvider =
    StateNotifierProvider.autoDispose<ScannerController, AsyncValue<QrScanResult?>>((ref) {
  return ScannerController(ScanQrUseCase(ref.watch(qrAttendanceRepositoryProvider)));
});
