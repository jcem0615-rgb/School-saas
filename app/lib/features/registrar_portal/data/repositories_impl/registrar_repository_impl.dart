import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../../faculty_portal/domain/entities/grade.dart';
import '../../domain/entities/document_release.dart';
import '../../domain/entities/student_summary.dart';
import '../../domain/entities/promotion.dart';
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
  Stream<List<StudentSummary>> watchStudents({int? limit, EducationLevel? educationLevel}) =>
      _remote.watchStudents(limit: limit, educationLevel: educationLevel);

  @override
  Future<List<StudentSummary>> fetchAllStudents() => _remote.fetchAllStudents();

  @override
  Stream<List<Grade>> watchStudentGrades(String studentId) =>
      _remote.watchStudentGrades(studentId);

  @override
  Stream<List<DocumentRelease>> watchDocumentReleases(String studentId) =>
      _remote.watchDocumentReleases(studentId);

  @override
  Future<Result<void>> recordDocumentRelease({
    required String studentId,
    required String studentName,
    required SchoolDocument document,
    required int copies,
    required String purpose,
    required String releasedToName,
    String? releasedToRelation,
    String? remarks,
  }) async {
    try {
      await _remote.recordDocumentRelease(
        studentId: studentId,
        studentName: studentName,
        document: document,
        copies: copies,
        purpose: purpose,
        releasedToName: releasedToName,
        releasedToRelation: releasedToRelation,
        remarks: remarks,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> setStudentPhoto({
    required String studentId,
    required String photoUrl,
  }) async {
    try {
      await _remote.setStudentPhoto(studentId: studentId, photoUrl: photoUrl);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<RegisterStudentOutcome>> registerStudent({
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    required String section,
    String? programId,
    DateTime? birthDate,
    String? email,
    String? phone,
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
        birthDate: birthDate,
        email: email,
        phone: phone,
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
    DateTime? birthDate,
    String? email,
    String? phone,
  }) async {
    try {
      await _remote.updateStudent(
        studentId: studentId,
        firstName: firstName,
        lastName: lastName,
        gradeLevel: gradeLevel,
        section: section,
        status: status.value,
        birthDate: birthDate,
        email: email,
        phone: phone,
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
    String? phone,
  }) async {
    try {
      final data = await _remote.provisionStudentAccount(
        studentId: studentId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        phone: phone,
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

  @override
  Future<Result<void>> setStudentBalance({
    required String studentId,
    required double balance,
    required String remarks,
  }) async {
    try {
      await _remote.setStudentBalance(
        studentId: studentId,
        balance: balance,
        remarks: remarks,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<List<Grade>> fetchGradesForSection(String section) =>
      _remote.fetchGradesForSection(section);

  @override
  Future<Set<String>> fetchRolledOverStudentIds(String schoolYear) =>
      _remote.fetchRolledOverStudentIds(schoolYear);

  @override
  Future<Result<RolloverOutcome>> runYearEndRollover({
    required String schoolYear,
    required List<PromotionDecision> decisions,
  }) async {
    try {
      final result = await _remote.runYearEndRollover(
        schoolYear: schoolYear,
        decisions: [for (final d in decisions) d.toMap()],
      );
      return Success(RolloverOutcome(
        applied: (result['applied'] as num?)?.toInt() ?? 0,
        skipped: (result['skipped'] as num?)?.toInt() ?? 0,
        schoolYear: result['schoolYear'] as String? ?? schoolYear,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
