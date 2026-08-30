import '../entities/bank_account.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/payment.dart';
import '../entities/payment_settings.dart';
import '../entities/payment_submission.dart';
import '../repositories/payment_repository.dart';

class WatchSubmissionsUseCase {
  final PaymentRepository _repository;
  const WatchSubmissionsUseCase(this._repository);

  Stream<List<PaymentSubmission>> call({bool pendingOnly = true}) =>
      _repository.watchSubmissions(pendingOnly: pendingOnly);
}

class WatchMySubmissionsUseCase {
  final PaymentRepository _repository;
  const WatchMySubmissionsUseCase(this._repository);

  Stream<List<PaymentSubmission>> call(String studentId) =>
      _repository.watchSubmissionsForStudent(studentId);
}

class SubmitOnlinePaymentUseCase {
  final PaymentRepository _repository;
  const SubmitOnlinePaymentUseCase(this._repository);

  Future<Result<void>> call({
    required String studentId,
    required String studentName,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    required String referenceNumber,
    String? destinationLabel,
    String? receiptUrl,
    String? receiptFileName,
  }) {
    if (studentId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('A student must be selected.')));
    }
    if (amount <= 0) {
      return Future.value(const Error(ValidationFailure('Amount must be greater than zero.')));
    }
    // The reference number is the one field a cashier can check against
    // the school's e-wallet, so a submission without it is unverifiable
    // and there is no point accepting it.
    if (referenceNumber.trim().isEmpty) {
      return Future.value(
        const Error(ValidationFailure('Enter the transaction reference number.')),
      );
    }
    return _repository.submitOnlinePayment(
      studentId: studentId.trim(),
      studentName: studentName.trim(),
      amount: amount,
      method: method,
      purpose: purpose,
      referenceNumber: referenceNumber.trim(),
      destinationLabel: destinationLabel,
      receiptUrl: receiptUrl,
      receiptFileName: receiptFileName,
    );
  }
}

class DecideSubmissionUseCase {
  final PaymentRepository _repository;
  const DecideSubmissionUseCase(this._repository);

  Future<Result<void>> call({
    required String submissionId,
    required bool approve,
    String? remarks,
  }) {
    if (submissionId.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Missing submission.')));
    }
    // A rejection with no reason leaves the family with nothing to act on;
    // an approval needs no justification beyond the reference matching.
    if (!approve && (remarks == null || remarks.trim().isEmpty)) {
      return Future.value(
        const Error(ValidationFailure('A reason is required when rejecting.')),
      );
    }
    return _repository.decideSubmission(
      submissionId: submissionId,
      approve: approve,
      remarks: remarks?.trim(),
    );
  }
}

class WatchPaymentSettingsUseCase {
  final PaymentRepository _repository;
  const WatchPaymentSettingsUseCase(this._repository);

  Stream<PaymentSettings> call() => _repository.watchPaymentSettings();
}

class UpdatePaymentSettingsUseCase {
  final PaymentRepository _repository;
  const UpdatePaymentSettingsUseCase(this._repository);

  Future<Result<void>> call({
    String? qrCodeUrl,
    String? qrCodeFileName,
    String? accountName,
    String? accountNumber,
    String? instructions,
    List<BankAccount>? bankAccounts,
  }) {
    return _repository.updatePaymentSettings(
      qrCodeUrl: qrCodeUrl,
      qrCodeFileName: qrCodeFileName,
      accountName: accountName,
      accountNumber: accountNumber,
      instructions: instructions,
      bankAccounts: bankAccounts,
    );
  }
}
