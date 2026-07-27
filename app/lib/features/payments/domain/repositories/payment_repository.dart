import '../../../../core/errors/result.dart';
import '../entities/payment.dart';

class RecordPaymentOutcome {
  final String paymentId;
  final String receiptNumber;
  final double newBalance;
  const RecordPaymentOutcome({
    required this.paymentId,
    required this.receiptNumber,
    required this.newBalance,
  });
}

abstract class PaymentRepository {
  Stream<List<Payment>> watchPaymentsForStudent(String studentId);

  /// Live balance for a student -- reads the denormalized `balance` field
  /// on the student's record, which recordPayment/recordRefund keep in
  /// sync server-side (see docs/08-payments.md for why the client never
  /// computes this itself).
  Stream<double> watchStudentBalance(String studentId);

  Future<Result<RecordPaymentOutcome>> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
  });

  Future<Result<void>> recordRefund({required String paymentId, required String reason});
}
