import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/daily_report.dart';
import '../repositories/staff_repository.dart';

class WatchMyDailyReportsUseCase {
  final StaffRepository _repository;
  const WatchMyDailyReportsUseCase(this._repository);

  Stream<List<DailyReport>> call() => _repository.watchMyDailyReports();
}

class SubmitDailyReportUseCase {
  final StaffRepository _repository;
  const SubmitDailyReportUseCase(this._repository);

  Future<Result<void>> call({required String date, required String content}) {
    final contentError = Validators.required(content, fieldName: 'Report content');
    if (contentError != null) return Future.value(Error(ValidationFailure(contentError)));
    return _repository.submitDailyReport(date: date, content: content.trim());
  }
}
