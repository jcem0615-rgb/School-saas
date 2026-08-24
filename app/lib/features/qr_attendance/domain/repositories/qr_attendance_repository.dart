import '../../../../core/errors/result.dart';
import '../entities/attendance_record.dart';
import '../entities/qr_scan_result.dart';

abstract class QrAttendanceRepository {
  /// Sends a scanned QR token to the server for processing. Never writes
  /// attendance directly from the client -- see markAttendance.ts for why
  /// (status computation, duplicate-scan handling, and audit logging all
  /// need to happen atomically and server-side).
  Future<Result<QrScanResult>> scanQrCode({required String qrToken, String? location});

  /// Attendance history for one person (self, or a linked child for a
  /// Parent, or any student/employee for staff-facing monitoring screens).
  Stream<List<AttendanceRecord>> watchAttendanceHistory(String personId, {int limit});
}
