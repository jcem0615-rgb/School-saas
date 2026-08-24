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
  /// [limit] null means the whole roster; a number means one page of it,
  /// surname order. [educationLevel] narrows the query itself rather than
  /// the page it returns -- see the datasource for why that distinction
  /// matters.
  Stream<List<StudentSummary>> watchStudents({int? limit, EducationLevel? educationLevel});

  /// The whole roster, once, for callers that must not miss anyone --
  /// export today. Deliberately separate from [watchStudents] so that
  /// reading everything is always a decision someone made.
  Future<List<StudentSummary>> fetchAllStudents();

  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    required List<GuardianContact> guardianContacts,
  });

  Future<Result<void>> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
    DateTime? birthDate,
  });

  /// Sets the student's ID photo to an already-uploaded [photoUrl].
  ///
  /// Uploading and recording are two steps on purpose: the upload can
  /// succeed and the write fail, and a caller that conflated them would
  /// report a photo saved that no record points at.
  Future<Result<void>> setStudentPhoto({
    required String studentId,
    required String photoUrl,
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
