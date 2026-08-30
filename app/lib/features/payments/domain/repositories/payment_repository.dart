import '../entities/bank_account.dart';
import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/result.dart';
import '../entities/assessment.dart';
import '../entities/fee_structure.dart';
import '../entities/installment.dart';
import '../entities/payment.dart';
import '../entities/payment_settings.dart';
import '../entities/payment_submission.dart';

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

class AssessmentOutcome {
  final String assessmentId;
  final double total;
  final double newBalance;
  const AssessmentOutcome({
    required this.assessmentId,
    required this.total,
    required this.newBalance,
  });
}

abstract class PaymentRepository {
  Stream<List<Payment>> watchPaymentsForStudent(String studentId);

  // -------------------------------------------------------------------
  // Fee assessment: what a student owes, and what it is for
  // -------------------------------------------------------------------
  //
  // A balance used to be a number with nothing behind it -- payments
  // reduced it and a registrar typed the opening figure by hand. These
  // are what let a family ask what they are being charged for and get an
  // answer.

  /// The school's published fee schedules, active and retired.
  Stream<List<FeeStructure>> watchFeeStructures();

  /// Publishes or edits a schedule. Director/Admin only in
  /// firestore.rules -- a registrar assesses fees but does not decide
  /// what they are.
  Future<Result<void>> saveFeeStructure({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    List<Installment> installments = const [],
    required bool isActive,
  });

  /// What one student has been charged, newest first.
  Stream<List<Assessment>> watchAssessments(String studentId);

  /// Charges fees and raises the balance in one server-side transaction.
  Future<Result<AssessmentOutcome>> assessStudentFees({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    List<Installment> installments,
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  });

  /// Reverses an assessment. Voiding rather than deleting -- see
  /// voidAssessment.ts for why the record has to survive.
  Future<Result<void>> voidAssessment({required String assessmentId, required String reason});

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

  // -------------------------------------------------------------------
  // Online payment: submit -> review -> apply
  // -------------------------------------------------------------------
  //
  // A student or parent cannot move a balance directly. They file a
  // submission with a reference number and a receipt image; a registrar
  // verifies it against the school's e-wallet and approves, and only that
  // approval creates the Payment. This is why recordPayment above is a
  // collector-only action -- see docs and firestore.rules.

  /// Files a claim that money was sent. Does not change the balance.
  Future<Result<void>> submitOnlinePayment({
    required String studentId,
    required String studentName,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    required String referenceNumber,
    String? destinationLabel,
    String? receiptUrl,
    String? receiptFileName,
  });

  /// A family's own submissions, so they can see whether theirs was
  /// approved rather than having to ask.
  Stream<List<PaymentSubmission>> watchSubmissionsForStudent(String studentId);

  /// The review queue. [pendingOnly] defaults to the working case -- a
  /// cashier wants what still needs deciding.
  Stream<List<PaymentSubmission>> watchSubmissions({bool pendingOnly = true});

  /// Approving records the corresponding Payment and adjusts the balance;
  /// rejecting records the reason and leaves the balance untouched.
  Future<Result<void>> decideSubmission({
    required String submissionId,
    required bool approve,
    String? remarks,
  });

  /// Where families should send money. Readable by the whole tenant.
  Stream<PaymentSettings> watchPaymentSettings();

  /// Registrar/admin only.
  Future<Result<void>> updatePaymentSettings({
    String? qrCodeUrl,
    String? qrCodeFileName,
    String? accountName,
    String? accountNumber,
    String? instructions,
    List<BankAccount>? bankAccounts,
  });
}
