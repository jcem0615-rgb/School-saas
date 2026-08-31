import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/admissions_remote_datasource.dart';
import '../../data/repositories_impl/admissions_repository_impl.dart';
import '../../domain/entities/applicant.dart';
import '../../domain/repositories/admissions_repository.dart';
import '../../domain/usecases/admissions_usecases.dart';

final admissionsRemoteDataSourceProvider = Provider<AdmissionsRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('AdmissionsRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return AdmissionsRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingAdmissionsUser(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final admissionsRepositoryProvider = Provider<AdmissionsRepository>((ref) {
  return AdmissionsRepositoryImpl(ref.watch(admissionsRemoteDataSourceProvider));
});

final applicantsStreamProvider = StreamProvider.autoDispose<List<Applicant>>((ref) {
  return WatchApplicantsUseCase(ref.watch(admissionsRepositoryProvider))();
});

/// The funnel, computed from whatever is on screen.
final admissionFunnelProvider = Provider.autoDispose<AdmissionFunnel>((ref) {
  return AdmissionFunnel.of(
    ref.watch(applicantsStreamProvider).valueOrNull ?? const <Applicant>[],
  );
});

/// Who the office should be ringing this morning.
///
/// A provider rather than something the screen computes, because the
/// dashboard shows the count and the screen shows the list, and two
/// places computing "who has gone quiet" is two places that can disagree
/// about it.
final applicantsNeedingFollowUpProvider = Provider.autoDispose<List<Applicant>>((ref) {
  return applicantsNeedingFollowUp(
    ref.watch(applicantsStreamProvider).valueOrNull ?? const <Applicant>[],
    asOf: DateTime.now(),
  );
});

class AdmissionsActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards, as elsewhere: this controller is autoDispose and
  // its repository rebuilds whenever authStateProvider emits. If that
  // lands mid-write the notifier is gone by the time the result returns.
  final AdmissionsRepository _repository;

  AdmissionsActionController(this._repository) : super(const AsyncData(null));

  Future<SavedApplicant?> saveApplicant({
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
    if (mounted) state = const AsyncLoading();
    final result = await SaveApplicantUseCase(_repository)(
      applicantId: applicantId,
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      programId: programId,
      guardianName: guardianName,
      guardianPhone: guardianPhone,
      guardianEmail: guardianEmail,
      source: source,
      notes: notes,
    );
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return null;
  }

  Future<bool> advance({
    required Applicant applicant,
    required AdmissionStage stage,
    DateTime? examScheduledFor,
    double? examScore,
    double? examMaxScore,
    double? reservationFee,
    String? reservationReference,
    String? notes,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await AdvanceApplicantUseCase(_repository)(
      applicant: applicant,
      stage: stage,
      examScheduledFor: examScheduledFor,
      examScore: examScore,
      examMaxScore: examMaxScore,
      reservationFee: reservationFee,
      reservationReference: reservationReference,
      notes: notes,
    );
    if (result case Success()) {
      if (mounted) state = const AsyncData(null);
      return true;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return false;
  }

  Future<EnrolledApplicant?> enrol({
    required Applicant applicant,
    required String section,
    required DateTime birthDate,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await EnrolApplicantUseCase(_repository)(
      applicant: applicant,
      section: section,
      birthDate: birthDate,
    );
    if (result case Success(:final value)) {
      if (mounted) state = const AsyncData(null);
      return value;
    } else if (result case Error(:final failure)) {
      if (mounted) state = AsyncError(failure.message, StackTrace.current);
    }
    return null;
  }
}

final admissionsActionControllerProvider = StateNotifierProvider.autoDispose<
    AdmissionsActionController, AsyncValue<void>>((ref) {
  return AdmissionsActionController(ref.watch(admissionsRepositoryProvider));
});
