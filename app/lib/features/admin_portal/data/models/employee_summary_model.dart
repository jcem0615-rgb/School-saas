
import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/user_roles.dart';
import '../../domain/entities/employee_summary.dart';

class EmployeeSummaryModel extends EmployeeSummary {
  const EmployeeSummaryModel({
    required super.uid,
    required super.firstName,
    required super.lastName,
    required super.email,
    super.phone,
    required super.role,
    required super.status,
    super.photoUrl,
    super.employeeInfo,
  });

  factory EmployeeSummaryModel.fromFirestore(String uid, Map<String, dynamic> data) {
    final rawInfo = data['employeeInfo'] as Map<String, dynamic>?;
    final rawDivision = rawInfo?['assignedDivision'] as String?;
    return EmployeeSummaryModel(
      uid: uid,
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      // Absent on every account provisioned before this field existed,
      // and null rather than '' when the office has none -- so "which
      // staff cannot recover their own account?" stays answerable.
      phone: switch (data['phone']) {
        final String p when p.trim().isNotEmpty => p.trim(),
        _ => null,
      },
      role: UserRole.fromString(data['role'] as String),
      status: UserAccountStatus.fromString(data['status'] as String? ?? 'active'),
      photoUrl: data['photoUrl'] as String?,
      employeeInfo: rawInfo == null
          ? null
          : EmployeeInfo(
              department: rawInfo['department'] as String? ?? '',
              position: rawInfo['position'] as String? ?? '',
              dateHired: DateTime.tryParse(rawInfo['dateHired'] as String? ?? '') ?? DateTime.now(),
              assignedDivision: rawDivision != null ? EducationLevel.fromString(rawDivision) : null,
              assignedDepartment: rawInfo['assignedDepartment'] as String?,
            ),
    );
  }
}
