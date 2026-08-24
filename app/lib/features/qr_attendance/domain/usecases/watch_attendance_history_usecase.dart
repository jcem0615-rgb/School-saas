import '../entities/attendance_record.dart';
import '../repositories/qr_attendance_repository.dart';

class WatchAttendanceHistoryUseCase {
  final QrAttendanceRepository _repository;
  const WatchAttendanceHistoryUseCase(this._repository);

  Stream<List<AttendanceRecord>> call(String personId, {int limit = 60}) =>
      _repository.watchAttendanceHistory(personId, limit: limit);
}
