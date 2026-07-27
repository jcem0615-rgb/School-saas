import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/program.dart';
import '../repositories/admin_repository.dart';

class WatchProgramsUseCase {
  final AdminRepository _repository;
  const WatchProgramsUseCase(this._repository);

  Stream<List<Program>> call() => _repository.watchPrograms();
}

class CreateProgramUseCase {
  final AdminRepository _repository;
  const CreateProgramUseCase(this._repository);

  Future<Result<void>> call({required String name, required String code, required String department}) {
    final nameError = Validators.required(name, fieldName: 'Program name');
    if (nameError != null) return Future.value(Error(ValidationFailure(nameError)));

    final codeError = Validators.required(code, fieldName: 'Program code');
    if (codeError != null) return Future.value(Error(ValidationFailure(codeError)));

    final deptError = Validators.required(department, fieldName: 'Department');
    if (deptError != null) return Future.value(Error(ValidationFailure(deptError)));

    return _repository.createProgram(name: name.trim(), code: code.trim(), department: department.trim());
  }
}
