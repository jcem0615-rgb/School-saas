import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/checklist_item.dart';
import '../../domain/entities/daily_report.dart';
import '../../domain/repositories/staff_repository.dart';
import '../datasources/staff_remote_datasource.dart';

class StaffRepositoryImpl implements StaffRepository {
  final StaffRemoteDataSource _remote;
  const StaffRepositoryImpl(this._remote);

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<ChecklistItem>> watchMyChecklist(String date) => _remote.watchMyChecklist(date);

  @override
  Future<Result<void>> addChecklistItem({required String task, required String date}) {
    return _guard(() => _remote.addChecklistItem(task: task, date: date));
  }

  @override
  Future<Result<void>> toggleChecklistItem({required String itemId, required bool completed}) {
    return _guard(() => _remote.toggleChecklistItem(itemId: itemId, completed: completed));
  }

  @override
  Stream<List<DailyReport>> watchMyDailyReports() => _remote.watchMyDailyReports();

  @override
  Future<Result<void>> submitDailyReport({required String date, required String content}) {
    return _guard(() => _remote.submitDailyReport(date: date, content: content));
  }

  @override
  Future<Result<void>> updateChecklistItem({required String itemId, required String task}) =>
      _guard(() => _remote.updateChecklistItem(itemId: itemId, task: task));

  @override
  Future<Result<void>> deleteChecklistItem(String itemId) =>
      _guard(() => _remote.softDeleteChecklistItem(itemId));
}
