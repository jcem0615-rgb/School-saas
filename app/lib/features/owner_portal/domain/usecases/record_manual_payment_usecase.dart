import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/invoice.dart';
import '../repositories/owner_repository.dart';

class RecordManualPaymentUseCase {
  final OwnerRepository _repository;
  const RecordManualPaymentUseCase(this._repository);

  Future<Result<void>> call({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required PaymentMethod method,
    String? referenceNumber,
  }) {
    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }
    if ((method == PaymentMethod.gcash || method == PaymentMethod.bankTransfer) &&
        (referenceNumber == null || referenceNumber.trim().isEmpty)) {
      return Future.value(
        const Error(ValidationFailure('A reference number is required for this payment method.')),
      );
    }
    return _repository.recordManualPayment(
      schoolId: schoolId,
      invoiceId: invoiceId,
      amount: amount,
      method: method,
      referenceNumber: referenceNumber?.trim(),
    );
  }
}
