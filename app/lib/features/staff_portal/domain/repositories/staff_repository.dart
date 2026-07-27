import '../../../../core/errors/result.dart';
import '../entities/checklist_item.dart';
import '../entities/daily_report.dart';

abstract class StaffRepository {
  Stream<List<ChecklistItem>> watchMyChecklist(String date);
  Future<Result<void>> addChecklistItem({required String task, required String date});
  Future<Result<void>> toggleChecklistItem({required String itemId, required bool completed});

  Stream<List<DailyReport>> watchMyDailyReports();
  Future<Result<void>> submitDailyReport({required String date, required String content});
}
