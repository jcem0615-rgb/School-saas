import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/qr_scan_result.dart';
import '../repositories/qr_attendance_repository.dart';

class ScanQrUseCase {
  final QrAttendanceRepository _repository;
  const ScanQrUseCase(this._repository);

  Future<Result<QrScanResult>> call({required String qrToken, String? location}) {
    if (qrToken.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('No QR code detected.')));
    }
    return _repository.scanQrCode(qrToken: qrToken.trim(), location: location);
  }
}
