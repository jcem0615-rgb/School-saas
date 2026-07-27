import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/user_roles.dart';

class EmployeeInfo {
  final String department;
  final String position;
  final DateTime dateHired;

  /// Optional data-isolation scope for Registrar/Faculty/Guidance staff
  /// (see docs/15-divisions-and-programs.md). Left unset, this staff
  /// member keeps normal cross-division access for their role -- setting
  /// it is what actually restricts them in firestore.rules, not just the UI.
  ///
  /// Distinct from [department] above: [department] is free-text HR
  /// metadata (e.g. "Maintenance", "Registrar's Office") shown on the
  /// Employee Detail screen; [assignedDepartment] specifically scopes
  /// data access and is only meaningful when [assignedDivision] is
  /// College, where it should match one of the school's [Program]
  /// departments.
  final EducationLevel? assignedDivision;
  final String? assignedDepartment;

  const EmployeeInfo({
    required this.department,
    required this.position,
    required this.dateHired,
    this.assignedDivision,
    this.assignedDepartment,
  });
}

/// A staff-facing account (any role except student/parent) as shown in
/// Admin's Employee Management list. Deliberately reuses the `users`
/// collection rather than a separate `employees` collection -- HR fields
/// (department/position/dateHired) live in `employeeInfo` on the same
/// document as the portal account, since every employee in this system
/// has a login (unlike students, who may not).
class EmployeeSummary {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final UserRole role;
  final UserAccountStatus status;
  final String? photoUrl;
  final EmployeeInfo? employeeInfo;

  const EmployeeSummary({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.role,
    required this.status,
    this.photoUrl,
    this.employeeInfo,
  });

  String get fullName => '$firstName $lastName';
}
