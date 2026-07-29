import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../auth/presentation/controllers/auth_controller.dart' show firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/owner_remote_datasource.dart';
import '../../data/repositories_impl/owner_repository_impl.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/revenue_summary.dart';
import '../../domain/entities/school_summary.dart';
import '../../domain/repositories/owner_repository.dart';
import '../../domain/usecases/pause_school_usecase.dart';
import '../../domain/usecases/record_manual_payment_usecase.dart';
import '../../domain/usecases/resume_school_usecase.dart';
import '../../domain/usecases/watch_invoices_usecase.dart';
import '../../domain/usecases/watch_revenue_summary_usecase.dart';
import '../../domain/usecases/watch_schools_usecase.dart';

final ownerRemoteDataSourceProvider = Provider<OwnerRemoteDataSource>((ref) {
  return OwnerRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

final ownerRepositoryProvider = Provider<OwnerRepository>((ref) {
  return OwnerRepositoryImpl(ref.watch(ownerRemoteDataSourceProvider));
});

/// Live list of every school on the platform, re-emitting on any school or
/// subscription change. Backs the Owner's School Management list screen.
final schoolsStreamProvider = StreamProvider<List<SchoolSummary>>((ref) {
  return WatchSchoolsUseCase(ref.watch(ownerRepositoryProvider))();
});

/// Headline dashboard metrics (daily/monthly/yearly revenue, active
/// school/student counts). Backed by a single denormalized document
/// maintained server-side -- cheap to watch regardless of platform size.
final revenueSummaryStreamProvider = StreamProvider<RevenueSummary>((ref) {
  return WatchRevenueSummaryUseCase(ref.watch(ownerRepositoryProvider))();
});

/// Family provider: invoices for one specific school, used on the school
/// detail / billing screen.
final invoicesStreamProvider =
    StreamProvider.family<List<Invoice>, String>((ref, schoolId) {
  return WatchInvoicesUseCase(ref.watch(ownerRepositoryProvider))(schoolId);
});

/// Drives the pause/resume/record-payment actions from school detail and
/// invoice screens. Kept separate from the read-side stream providers
/// above since actions need loading/error state, streams don't.
class OwnerActionController extends StateNotifier<AsyncValue<void>> {
  final PauseSchoolUseCase _pauseSchool;
  final ResumeSchoolUseCase _resumeSchool;
  final RecordManualPaymentUseCase _recordPayment;

  OwnerActionController({
    required PauseSchoolUseCase pauseSchool,
    required ResumeSchoolUseCase resumeSchool,
    required RecordManualPaymentUseCase recordPayment,
  })  : _pauseSchool = pauseSchool,
        _resumeSchool = resumeSchool,
        _recordPayment = recordPayment,
        super(const AsyncData(null));

  Future<bool> pauseSchool({required String schoolId, required String reason}) async {
    state = const AsyncLoading();
    final result = await _pauseSchool(schoolId: schoolId, reason: reason);
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  Future<bool> resumeSchool(String schoolId) async {
    state = const AsyncLoading();
    final result = await _resumeSchool(schoolId: schoolId);
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  Future<bool> recordManualPayment({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required PaymentMethod method,
    String? referenceNumber,
  }) async {
    state = const AsyncLoading();
    final result = await _recordPayment(
      schoolId: schoolId,
      invoiceId: invoiceId,
      amount: amount,
      method: method,
      referenceNumber: referenceNumber,
    );
    return switch (result) {
      Success() => _succeed(),
      Error(:final failure) => _fail(failure.message),
    };
  }

  bool _succeed() {
    state = const AsyncData(null);
    return true;
  }

  bool _fail(String message) {
    state = AsyncError(message, StackTrace.current);
    return false;
  }
}

final ownerActionControllerProvider =
    StateNotifierProvider<OwnerActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(ownerRepositoryProvider);
  return OwnerActionController(
    pauseSchool: PauseSchoolUseCase(repo),
    resumeSchool: ResumeSchoolUseCase(repo),
    recordPayment: RecordManualPaymentUseCase(repo),
  );
});
