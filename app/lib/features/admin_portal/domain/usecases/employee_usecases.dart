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

// Employee roles the Admin Portal offers on the new-employee form. Kept
// in sync with (but intentionally a client-side subset preview of) the
// server-side PROVISIONING_MATRIX in provisionUser.ts -- this is a UX
// nicety (don't show a role in the dropdown the server will reject), not
// the security boundary; the server re-validates regardless.
//
// A subset in one direction only: the server also lets an Admin create
// student and parent accounts, and those are not here because they are
// not made on this form. A student account is minted against a student
// record, in the Registrar's student detail screen, so that the account
// and the record are linked at the moment the account exists.
const adminProvisionableRoles = [
  UserRole.director,
  UserRole.principal,
  // An admin office is a department, not a person. Without this the only
  // account that could create a second Admin was the Owner's -- the
  // vendor's -- which made covering for one person's sick day a support
  // ticket.
  UserRole.admin,
  UserRole.registrar,
  UserRole.faculty,
  UserRole.staff,
  UserRole.guidance,
];

/// Roles the employee spreadsheet import will mint.
///
/// Deliberately narrower than [adminProvisionableRoles]: the form is one
/// account at a time, typed, with the role picked from a dropdown in
/// front of somebody. An import is three hundred rows from a file, and a
/// role column that says "admin" all the way down -- a mistake, or a
/// paste from the wrong sheet -- would hand out three hundred accounts
/// that can each create three hundred more. Leadership accounts are made
/// one at a time, on purpose.
const importableEmployeeRoles = [
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
    String? phone,
    EmployeeInfo? employeeInfo,
  }) {
    final firstNameError = Validators.required(firstName, fieldName: 'First name');
    if (firstNameError != null) return Future.value(Error(ValidationFailure(firstNameError)));

    final lastNameError = Validators.required(lastName, fieldName: 'Last name');
    if (lastNameError != null) return Future.value(Error(ValidationFailure(lastNameError)));

    final emailError = Validators.email(email);
    if (emailError != null) return Future.value(Error(ValidationFailure(emailError)));

    // Optional, and checked when present. An employee account works
    // without a number -- it just cannot be recovered by phone, and the
    // office cannot ring this person when a class has nobody in front
    // of it. Provisioning is the moment the number is on the form in
    // front of them, so it is the moment worth asking.
    final phoneError = Validators.optionalPhilippineMobile(phone);
    if (phoneError != null) return Future.value(Error(ValidationFailure(phoneError)));

    final trimmedPhone = phone?.trim();
    return _repository.createEmployee(
      role: role,
      firstName: firstName.trim(),
      lastName: lastName.trim(),
      email: email.trim(),
      phone: (trimmedPhone == null || trimmedPhone.isEmpty) ? null : trimmedPhone,
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
