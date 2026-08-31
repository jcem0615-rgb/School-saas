import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/applicant.dart';
import '../../domain/repositories/admissions_repository.dart';
import '../datasources/admissions_remote_datasource.dart';

class AdmissionsRepositoryImpl implements AdmissionsRepository {
  final AdmissionsRemoteDataSource _remote;
  const AdmissionsRepositoryImpl(this._remote);

  @override
  Stream<List<Applicant>> watchApplicants() => _remote.watchApplicants();

  @override
  Future<Result<SavedApplicant>> saveApplicant({
    String? applicantId,
    required String firstName,
    required String lastName,
    String? middleName,
    required EducationLevel educationLevel,
    required String gradeLevel,
    String? programId,
    required String guardianName,
    required String guardianPhone,
    String? guardianEmail,
    String? source,
    String? notes,
  }) async {
    try {
      final data = await _remote.saveApplicant({
        if (applicantId != null) 'applicantId': applicantId,
        'firstName': firstName,
        'lastName': lastName,
        'middleName': middleName,
        'educationLevel': educationLevel.value,
        'gradeLevel': gradeLevel,
        'programId': programId,
        'guardianName': guardianName,
        'guardianPhone': guardianPhone,
        'guardianEmail': guardianEmail,
        'source': source,
        'notes': notes,
      });
      return Success(SavedApplicant(
        applicantId: data['applicantId'] as String? ?? applicantId ?? '',
        referenceNumber: data['referenceNumber'] as String?,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> advanceApplicant({
    required String applicantId,
    required AdmissionStage stage,
    DateTime? examScheduledFor,
    double? examScore,
    double? examMaxScore,
    double? reservationFee,
    String? reservationReference,
    String? notes,
  }) async {
    try {
      await _remote.advanceApplicant({
        'applicantId': applicantId,
        'stage': stage.value,
        if (examScheduledFor != null)
          'examScheduledFor': examScheduledFor.toIso8601String(),
        if (examScore != null) 'examScore': examScore,
        if (examMaxScore != null) 'examMaxScore': examMaxScore,
        if (reservationFee != null) 'reservationFee': reservationFee,
        if (reservationReference != null) 'reservationReference': reservationReference,
        if (notes != null) 'notes': notes,
      });
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<EnrolledApplicant>> enrolApplicant({
    required String applicantId,
    required String section,
    required DateTime birthDate,
  }) async {
    try {
      final data = await _remote.enrolApplicant(
        applicantId: applicantId,
        section: section,
        birthDate: birthDate,
      );
      return Success(EnrolledApplicant(
        studentId: data['studentId'] as String? ?? '',
        studentNumber: data['studentNumber'] as String? ?? '',
        openingCredit: (data['openingCredit'] as num?)?.toDouble() ?? 0,
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
