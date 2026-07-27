import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/student_summary.dart';
import '../../domain/repositories/registrar_repository.dart';
import '../datasources/registrar_remote_datasource.dart';

class RegistrarRepositoryImpl implements RegistrarRepository {
  final RegistrarRemoteDataSource _remote;
  const RegistrarRepositoryImpl(this._remote);

  Map<String, dynamic> _guardianToMap(GuardianContact g) => {
        'name': g.name,
        'relationship': g.relationship,
        'phone': g.phone,
        'email': g.email,
      };

  @override
  Stream<List<StudentSummary>> watchStudents() => _remote.watchStudents();

  @override
  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    required List<GuardianContact> guardianContacts,
  }) async {
    try {
      final data = await _remote.registerStudent(
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        educationLevel: educationLevel.value,
        gradeLevel: gradeLevel,
        section: section,
        programId: programId,
        guardianContacts: guardianContacts.map(_guardianToMap).toList(),
      );
      return Success(RegisterStudentOutcome(
        studentId: data['studentId'] as String,
        studentNumber: data['studentNumber'] as String,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> updateStudent({
    required String studentId,
    required String firstName,
    required String lastName,
    required String gradeLevel,
    required String section,
    required StudentStatus status,
  }) async {
    try {
      await _remote.updateStudent(
        studentId: studentId,
        firstName: firstName,
        lastName: lastName,
        gradeLevel: gradeLevel,
        section: section,
        status: status.value,
      );
      return const Success(null);
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<ProvisionStudentAccountOutcome>> provisionStudentAccount({
    required String studentId,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    try {
      final data = await _remote.provisionStudentAccount(
        studentId: studentId,
        firstName: firstName,
        lastName: lastName,
        email: email,
      );
      return Success(ProvisionStudentAccountOutcome(
        uid: data['uid'] as String,
        tempPassword: data['tempPassword'] as String,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
