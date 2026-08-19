import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/attendance_record.dart';
import '../../domain/entities/qr_scan_result.dart';
import '../../domain/repositories/qr_attendance_repository.dart';
import '../datasources/qr_attendance_remote_datasource.dart';

class QrAttendanceRepositoryImpl implements QrAttendanceRepository {
  final QrAttendanceRemoteDataSource _remote;
  const QrAttendanceRepositoryImpl(this._remote);

  @override
  Future<Result<QrScanResult>> scanQrCode({required String qrToken, String? location}) async {
    try {
      final result = await _remote.scanQrCode(qrToken: qrToken, location: location);
      return Success(result);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory(String personId, {int limit = 60}) {
    return _remote.watchAttendanceHistory(personId, limit: limit);
  }
}
