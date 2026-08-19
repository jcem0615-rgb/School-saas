import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/payment.dart';
import '../repositories/payment_repository.dart';

class RecordPaymentUseCase {
  final PaymentRepository _repository;
  const RecordPaymentUseCase(this._repository);

  Future<Result<RecordPaymentOutcome>> call({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A student must be selected.')));
    }
    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }
    if ((method == PaymentMethod.gcash || method == PaymentMethod.bankTransfer) &&
        (referenceNumber == null || referenceNumber.trim().isEmpty)) {
      return Future.value(
        const Error(ValidationFailure('A reference number is required for this payment method.')),
      );
    }
    return _repository.recordPayment(
      studentId: studentId.trim(),
      amount: amount,
      method: method,
      purpose: purpose,
      referenceNumber: referenceNumber?.trim(),
    );
  }
}
