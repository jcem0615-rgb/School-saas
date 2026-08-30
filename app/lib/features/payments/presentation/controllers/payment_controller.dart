import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/bank_account.dart';
import '../../../../core/errors/result.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/payment_remote_datasource.dart';
import '../../data/repositories_impl/payment_repository_impl.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/payment_settings.dart';
import '../../domain/entities/payment_submission.dart';
import '../../../../core/constants/education_level.dart';
import '../../domain/entities/assessment.dart';
import '../../domain/entities/fee_structure.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/usecases/fee_usecases.dart';
import '../../domain/usecases/record_payment_usecase.dart';
import '../../domain/usecases/record_refund_usecase.dart';
import '../../domain/usecases/submission_usecases.dart';
import '../../domain/usecases/watch_payments_usecase.dart';

final paymentRemoteDataSourceProvider = Provider<PaymentRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('PaymentRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return PaymentRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    schoolId: user.schoolId!,
    actingUser: ActingPayer(
      uid: user.uid,
      name: user.fullName,
      role: user.role.value,
    ),
  );
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepositoryImpl(ref.watch(paymentRemoteDataSourceProvider));
});

final paymentsForStudentStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, studentId) {
  return WatchPaymentsForStudentUseCase(ref.watch(paymentRepositoryProvider))(studentId);
});

final studentBalanceStreamProvider =
    StreamProvider.autoDispose.family<double, String>((ref, studentId) {
  return WatchStudentBalanceUseCase(ref.watch(paymentRepositoryProvider))(studentId);
});

/// The school's e-wallet details. Watched by the pay screen (to show the
/// QR) and by the registrar's settings screen (to edit it).
final paymentSettingsProvider = StreamProvider.autoDispose<PaymentSettings>((ref) {
  return WatchPaymentSettingsUseCase(ref.watch(paymentRepositoryProvider))();
});

/// The registrar's review queue.
final pendingSubmissionsProvider =
    StreamProvider.autoDispose<List<PaymentSubmission>>((ref) {
  return WatchSubmissionsUseCase(ref.watch(paymentRepositoryProvider))(pendingOnly: true);
});

/// Every submission, decided or not -- used for the "all" filter.
final allSubmissionsProvider = StreamProvider.autoDispose<List<PaymentSubmission>>((ref) {
  return WatchSubmissionsUseCase(ref.watch(paymentRepositoryProvider))(pendingOnly: false);
});

/// A family's own submissions, so they can see the outcome of a claim.
final mySubmissionsProvider =
    StreamProvider.autoDispose.family<List<PaymentSubmission>, String>((ref, studentId) {
  return WatchMySubmissionsUseCase(ref.watch(paymentRepositoryProvider))(studentId);
});

/// The school's published fee schedules. Not autoDispose: the assessment
/// screen and the fee-structure screen both read it, and it is a handful
/// of documents that change a few times a year.
final feeStructuresProvider = StreamProvider<List<FeeStructure>>((ref) {
  return WatchFeeStructuresUseCase(ref.watch(paymentRepositoryProvider))();
});

/// What one student has been charged, newest first. This is what turns a
/// balance from a number into an answer.
final assessmentsForStudentProvider =
    StreamProvider.autoDispose.family<List<Assessment>, String>((ref, studentId) {
  return WatchAssessmentsUseCase(ref.watch(paymentRepositoryProvider))(studentId);
});

class PaymentActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final RecordPaymentUseCase _recordPayment;
  final RecordRefundUseCase _recordRefund;
  final SubmitOnlinePaymentUseCase _submitOnlinePayment;
  final DecideSubmissionUseCase _decideSubmission;
  final UpdatePaymentSettingsUseCase _updatePaymentSettings;
  final SaveFeeStructureUseCase _saveFeeStructure;
  final AssessStudentFeesUseCase _assessStudentFees;
  final VoidAssessmentUseCase _voidAssessment;

  PaymentActionController({
    required RecordPaymentUseCase recordPayment,
    required RecordRefundUseCase recordRefund,
    required SubmitOnlinePaymentUseCase submitOnlinePayment,
    required DecideSubmissionUseCase decideSubmission,
    required UpdatePaymentSettingsUseCase updatePaymentSettings,
    required SaveFeeStructureUseCase saveFeeStructure,
    required AssessStudentFeesUseCase assessStudentFees,
    required VoidAssessmentUseCase voidAssessment,
  })  : _recordPayment = recordPayment,
        _recordRefund = recordRefund,
        _submitOnlinePayment = submitOnlinePayment,
        _decideSubmission = decideSubmission,
        _updatePaymentSettings = updatePaymentSettings,
        _saveFeeStructure = saveFeeStructure,
        _assessStudentFees = assessStudentFees,
        _voidAssessment = voidAssessment,
        super(const AsyncData(null));

  Future<bool> saveFeeStructure({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    bool isActive = true,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _saveFeeStructure(
      structureId: structureId,
      name: name,
      educationLevel: educationLevel,
      gradeLevel: gradeLevel,
      schoolYear: schoolYear,
      items: items,
      isActive: isActive,
    );
    return _boolFrom(result);
  }

  /// Charges fees. Returns the outcome so the screen can say what the
  /// balance became without waiting for the stream to tick.
  Future<AssessmentOutcome?> assessStudentFees({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _assessStudentFees(
      studentId: studentId,
      schoolYear: schoolYear,
      items: items,
      sourceStructureId: sourceStructureId,
      sourceStructureName: sourceStructureName,
      remarks: remarks,
    );
    return switch (result) {
      Success(:final value) => _succeedWith(value),
      Error(:final failure) => _failWith(failure.message),
    };
  }

  Future<bool> voidAssessment({
    required String assessmentId,
    required String reason,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _boolFrom(await _voidAssessment(assessmentId: assessmentId, reason: reason));
  }

  bool _boolFrom(Result<void> result) {
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  AssessmentOutcome? _succeedWith(AssessmentOutcome value) {
    if (mounted) state = const AsyncData(null);
    return value;
  }

  AssessmentOutcome? _failWith(String message) {
    if (mounted) state = AsyncError(message, StackTrace.current);
    return null;
  }

  /// Returns the full outcome on success -- receipt number for navigating
  /// to the receipt, and the resulting balance so a payment screen can
  /// confirm what is still owed without waiting for the balance stream to
  /// tick. Null on failure; the error is already in [state] for the UI to
  /// surface via ref.listen.
  Future<RecordPaymentOutcome?> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _recordPayment(
      studentId: studentId,
      amount: amount,
      method: method,
      purpose: purpose,
      referenceNumber: referenceNumber,
    );
    return switch (result) {
      Success(:final value) => _succeed(value),
      Error(:final failure) => _fail(failure.message),
    };
  }

  /// Files a claim that money was sent. Returns true on success. Nothing
  /// is credited until a registrar approves it.
  Future<bool> submitOnlinePayment({
    required String studentId,
    required String studentName,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    required String referenceNumber,
    String? destinationLabel,
    String? receiptUrl,
    String? receiptFileName,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _submitOnlinePayment(
      studentId: studentId,
      studentName: studentName,
      amount: amount,
      method: method,
      purpose: purpose,
      referenceNumber: referenceNumber,
      destinationLabel: destinationLabel,
      receiptUrl: receiptUrl,
      receiptFileName: receiptFileName,
    );
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<bool> decideSubmission({
    required String submissionId,
    required bool approve,
    String? remarks,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _decideSubmission(
      submissionId: submissionId,
      approve: approve,
      remarks: remarks,
    );
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<bool> updatePaymentSettings({
    String? qrCodeUrl,
    String? qrCodeFileName,
    String? accountName,
    String? accountNumber,
    String? instructions,
    List<BankAccount>? bankAccounts,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _updatePaymentSettings(
      qrCodeUrl: qrCodeUrl,
      qrCodeFileName: qrCodeFileName,
      accountName: accountName,
      accountNumber: accountNumber,
      instructions: instructions,
      bankAccounts: bankAccounts,
    );
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  Future<bool> recordRefund({required String paymentId, required String reason}) async {
    if (mounted) state = const AsyncLoading();
    final result = await _recordRefund(paymentId: paymentId, reason: reason);
    return switch (result) {
      Success() => () {
          if (mounted) state = const AsyncData(null);
          return true;
        }(),
      Error(:final failure) => () {
          if (mounted) state = AsyncError(failure.message, StackTrace.current);
          return false;
        }(),
    };
  }

  RecordPaymentOutcome? _succeed(RecordPaymentOutcome value) {
    if (mounted) state = const AsyncData(null);
    return value;
  }

  RecordPaymentOutcome? _fail(String message) {
    if (mounted) state = AsyncError(message, StackTrace.current);
    return null;
  }
}

final paymentActionControllerProvider =
    StateNotifierProvider.autoDispose<PaymentActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(paymentRepositoryProvider);
  return PaymentActionController(
    recordPayment: RecordPaymentUseCase(repo),
    recordRefund: RecordRefundUseCase(repo),
    submitOnlinePayment: SubmitOnlinePaymentUseCase(repo),
    decideSubmission: DecideSubmissionUseCase(repo),
    updatePaymentSettings: UpdatePaymentSettingsUseCase(repo),
    saveFeeStructure: SaveFeeStructureUseCase(repo),
    assessStudentFees: AssessStudentFeesUseCase(repo),
    voidAssessment: VoidAssessmentUseCase(repo),
  );
});
