import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';
import '../datasources/payment_remote_datasource.dart';

class PaymentRepositoryImpl implements PaymentRepository {
  final PaymentRemoteDataSource _remote;
  const PaymentRepositoryImpl(this._remote);

  @override
  Stream<List<Payment>> watchPaymentsForStudent(String studentId) =>
      _remote.watchPaymentsForStudent(studentId);

  @override
  Stream<double> watchStudentBalance(String studentId) => _remote.watchStudentBalance(studentId);

  @override
  Future<Result<RecordPaymentOutcome>> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
  }) async {
    try {
      final data = await _remote.recordPayment(
        studentId: studentId,
        amount: amount,
        method: method.value,
        purpose: purpose.value,
        referenceNumber: referenceNumber,
      );
      return Success(RecordPaymentOutcome(
        paymentId: data['paymentId'] as String,
        receiptNumber: data['receiptNumber'] as String,
        newBalance: (data['newBalance'] as num).toDouble(),
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> recordRefund({required String paymentId, required String reason}) async {
    try {
      await _remote.recordRefund(paymentId: paymentId, reason: reason);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
