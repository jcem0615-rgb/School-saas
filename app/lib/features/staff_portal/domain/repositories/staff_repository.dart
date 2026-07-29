import '../../../../core/errors/result.dart';
import '../entities/checklist_item.dart';
import '../entities/daily_report.dart';

abstract class StaffRepository {
  Stream<List<ChecklistItem>> watchMyChecklist(String date);
  Future<Result<void>> addChecklistItem({required String task, required String date});
  Future<Result<void>> toggleChecklistItem({required String itemId, required bool completed});
  Future<Result<void>> updateChecklistItem({required String itemId, required String task});

  /// Soft delete. Note there is deliberately no delete or edit for daily
  /// reports: firestore.rules makes that collection immutable, because a
  /// daily work log is a point-in-time record and corrections are filed as
  /// a new entry rather than an edit.
  Future<Result<void>> deleteChecklistItem(String itemId);

  Stream<List<DailyReport>> watchMyDailyReports();
  Future<Result<void>> submitDailyReport({required String date, required String content});
}
