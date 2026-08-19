import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../repositories/payment_repository.dart';

class RecordRefundUseCase {
  final PaymentRepository _repository;
  const RecordRefundUseCase(this._repository);

  Future<Result<void>> call({required String paymentId, required String reason}) {
    if (reason.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A reason is required to process a refund.')));
    }
    return _repository.recordRefund(paymentId: paymentId, reason: reason.trim());
  }
}
