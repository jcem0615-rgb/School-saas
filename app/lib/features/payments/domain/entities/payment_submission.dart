import 'payment.dart';

enum SubmissionStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  final String value;
  const SubmissionStatus(this.value);

  static SubmissionStatus fromString(String value) =>
      SubmissionStatus.values.firstWhere((s) => s.value == value,
          orElse: () => SubmissionStatus.pending);

  String get displayLabel => switch (this) {
        SubmissionStatus.pending => 'Awaiting review',
        SubmissionStatus.approved => 'Approved',
        SubmissionStatus.rejected => 'Rejected',
      };
}

/// A claim that money was sent, awaiting verification.
///
/// This is deliberately NOT a [Payment]. A payment is a fact the school
/// asserts -- it has a receipt number and it moves the balance. A
/// submission is something a family says happened: they scanned the
/// school's QR, sent money from their own e-wallet, and are now producing
/// a reference number and a screenshot as evidence.
///
/// Keeping them as separate records is what makes the approval step
/// meaningful. Nothing here touches the student's balance; only a
/// registrar approving it creates the corresponding Payment, and at that
/// point [resultingPaymentId] links the two so the trail from "family
/// claimed" to "school recorded" stays intact.
class PaymentSubmission {
  final String id;
  final String studentId;
  final String studentName;

  /// Who filed it -- the student themself or a linked parent. Kept because
  /// "who says they paid" is part of what a reviewer is verifying.
  final String submittedByName;
  final String submittedByRole;

  final double amount;
  final PaymentMethod method;
  final PaymentPurpose purpose;

  /// The e-wallet reference the family read off their own receipt. Required:
  /// it is the one field a cashier can check against the school's account.
  final String referenceNumber;

  /// Screenshot or photo of the receipt.
  final String? receiptUrl;
  final String? receiptFileName;

  final SubmissionStatus status;
  final String? reviewedByName;
  final DateTime? reviewedAt;
  final String? decisionRemarks;

  /// Set when approved -- the Payment this submission produced.
  final String? resultingPaymentId;

  final DateTime submittedAt;

  const PaymentSubmission({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.submittedByName,
    required this.submittedByRole,
    required this.amount,
    required this.method,
    required this.purpose,
    required this.referenceNumber,
    required this.status,
    required this.submittedAt,
    this.receiptUrl,
    this.receiptFileName,
    this.reviewedByName,
    this.reviewedAt,
    this.decisionRemarks,
    this.resultingPaymentId,
  });

  bool get isPending => status == SubmissionStatus.pending;
}
