import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/checklist_item.dart';
import '../repositories/staff_repository.dart';

class WatchMyChecklistUseCase {
  final StaffRepository _repository;
  const WatchMyChecklistUseCase(this._repository);

  Stream<List<ChecklistItem>> call(String date) => _repository.watchMyChecklist(date);
}

class AddChecklistItemUseCase {
  final StaffRepository _repository;
  const AddChecklistItemUseCase(this._repository);

  Future<Result<void>> call({required String task, required String date}) {
    final taskError = Validators.required(task, fieldName: 'Task');
    if (taskError != null) return Future.value(Error(ValidationFailure(taskError)));
    return _repository.addChecklistItem(task: task.trim(), date: date);
  }
}

class ToggleChecklistItemUseCase {
  final StaffRepository _repository;
  const ToggleChecklistItemUseCase(this._repository);

  Future<Result<void>> call({required String itemId, required bool completed}) =>
      _repository.toggleChecklistItem(itemId: itemId, completed: completed);
}
