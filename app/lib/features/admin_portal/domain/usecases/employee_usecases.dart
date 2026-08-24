import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/utils/validators.dart';
import '../entities/employee_summary.dart';
import '../repositories/admin_repository.dart';

class WatchEmployeesUseCase {
  final AdminRepository _repository;
  const WatchEmployeesUseCase(this._repository);

  Stream<List<EmployeeSummary>> call() => _repository.watchEmployees();
}

// Roles Admin Portal is permitted to provision. Kept in sync with (but
// intentionally a client-side subset preview of) the server-side
// PROVISIONING_MATRIX in provisionUser.ts -- this is a UX nicety (don't
// show a role in the dropdown the server will reject), not the security
// boundary; the server re-validates regardless.
const adminProvisionableRoles = [
  UserRole.principal,
  UserRole.registrar,
  UserRole.faculty,
  UserRole.staff,
  UserRole.guidance,
];

class CreateEmployeeUseCase {
  final AdminRepository _repository;
  const CreateEmployeeUseCase(this._repository);

  Future<Result<CreateEmployeeOutcome>> call({
    required UserRole role,
    required String firstName,
    required String lastName,
    required String email,
    EmployeeInfo? employeeInfo,
  }) {
    final firstNameError = Validators.required(firstName, fieldName: 'First name');
    if (firstNameError != null) return Future.value(Error(ValidationFailure(firstNameError)));

    final lastNameError = Validators.required(lastName, fieldName: 'Last name');
    if (lastNameError != null) return Future.value(Error(ValidationFailure(lastNameError)));

    final emailError = Validators.email(email);
    if (emailError != null) return Future.value(Error(ValidationFailure(emailError)));

    return _repository.createEmployee(
      role: role,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      employeeInfo: employeeInfo,
    );
  }
}

class UpdateEmployeeInfoUseCase {
  final AdminRepository _repository;
  const UpdateEmployeeInfoUseCase(this._repository);

  Future<Result<void>> call({required String uid, required EmployeeInfo employeeInfo}) {
    final deptError = Validators.required(employeeInfo.department, fieldName: 'Department');
    if (deptError != null) return Future.value(Error(ValidationFailure(deptError)));

    final positionError = Validators.required(employeeInfo.position, fieldName: 'Position');
    if (positionError != null) return Future.value(Error(ValidationFailure(positionError)));

    return _repository.updateEmployeeInfo(uid: uid, employeeInfo: employeeInfo);
  }
}

class SetUserStatusUseCase {
  final AdminRepository _repository;
  const SetUserStatusUseCase(this._repository);

  Future<Result<void>> call({required String uid, required bool active}) =>
      _repository.setUserStatus(uid: uid, active: active);
}

class ResetUserPasswordUseCase {
  final AdminRepository _repository;
  const ResetUserPasswordUseCase(this._repository);

  Future<Result<String>> call(String uid) => _repository.resetUserPassword(uid);
}
