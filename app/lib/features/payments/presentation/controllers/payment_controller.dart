import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/payment_remote_datasource.dart';
import '../../data/repositories_impl/payment_repository_impl.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/usecases/record_payment_usecase.dart';
import '../../domain/usecases/record_refund_usecase.dart';
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

class PaymentActionController extends StateNotifier<AsyncValue<void>> {
  // `mounted` guards below: these action controllers are autoDispose, and
  // the repositories they depend on rebuild whenever authStateProvider
  // emits. If that lands while a write is in flight the notifier is gone
  // by the time the result returns, and assigning `state` then throws
  // "used after dispose" -- which surfaces as an action that silently does
  // nothing even though the write succeeded.
  final RecordPaymentUseCase _recordPayment;
  final RecordRefundUseCase _recordRefund;

  PaymentActionController({
    required RecordPaymentUseCase recordPayment,
    required RecordRefundUseCase recordRefund,
  })  : _recordPayment = recordPayment,
        _recordRefund = recordRefund,
        super(const AsyncData(null));

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
  );
});
