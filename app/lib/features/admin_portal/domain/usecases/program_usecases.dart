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

class UpdateProgramUseCase {
  final AdminRepository _repository;
  const UpdateProgramUseCase(this._repository);

  Future<Result<void>> call({
    required String programId,
    required String name,
    required String code,
    required String department,
  }) {
    if (programId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing program.')));
    }
    final nameError = Validators.required(name, fieldName: 'Program name');
    if (nameError != null) return Future.value(Error(ValidationFailure(nameError)));

    final deptError = Validators.required(department, fieldName: 'Department');
    if (deptError != null) return Future.value(Error(ValidationFailure(deptError)));

    return _repository.updateProgram(
      programId: programId,
      name: name.trim(),
      code: code.trim(),
      department: department.trim(),
    );
  }
}

/// Students keep programName/department denormalized onto their own record
/// at registration (docs/15-divisions-and-programs.md), so removing a
/// program from the catalogue never rewrites or orphans enrolled students.
class DeleteProgramUseCase {
  final AdminRepository _repository;
  const DeleteProgramUseCase(this._repository);

  Future<Result<void>> call(String programId) {
    if (programId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing program.')));
    }
    return _repository.deleteProgram(programId);
  }
}
