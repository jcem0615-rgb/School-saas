import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/result.dart';
import '../entities/student_summary.dart';

class RegisterStudentOutcome {
  final String studentId;
  final String studentNumber;
  const RegisterStudentOutcome({required this.studentId, required this.studentNumber});
}

class ProvisionStudentAccountOutcome {
  final String uid;
  final String tempPassword;
  const ProvisionStudentAccountOutcome({required this.uid, required this.tempPassword});
}

abstract class RegistrarRepository {
  Stream<List<StudentSummary>> watchStudents();

  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    required List<GuardianContact> guardianContacts,
  });

  Future<Result<void>> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
  });

  /// Creates a Student Portal login for an existing academic record and
  /// links them (see provisionUser.ts's linkedStudentId handling).
  Future<Result<ProvisionStudentAccountOutcome>> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  });

  /// Sets the student's assessed balance. Server-side only -- see the
  /// datasource for why this cannot be an ordinary field update.
  Future<Result<void>> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  });
}
