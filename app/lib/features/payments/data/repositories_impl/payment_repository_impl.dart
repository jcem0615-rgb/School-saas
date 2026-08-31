import '../../domain/entities/bank_account.dart';
import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/assessment.dart';
import '../../domain/entities/fee_structure.dart';
import '../../domain/entities/discount.dart';
import '../../domain/entities/installment.dart';
import '../../domain/entities/receipt_booklet.dart';
import '../../domain/entities/subsidy.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/payment_settings.dart';
import '../../domain/entities/payment_submission.dart';
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
  Stream<List<FeeStructure>> watchFeeStructures() => _remote.watchFeeStructures();

  @override
  Future<Result<void>> saveFeeStructure({
    String? structureId,
    required String name,
    required EducationLevel educationLevel,
    String? gradeLevel,
    required String schoolYear,
    required List<FeeItem> items,
    List<Installment> installments = const [],
    required bool isActive,
  }) async {
    try {
      await _remote.saveFeeStructure(
        structureId: structureId,
        name: name,
        educationLevel: educationLevel,
        gradeLevel: gradeLevel,
        schoolYear: schoolYear,
        items: items,
        installments: installments,
        isActive: isActive,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<List<Assessment>> watchAssessments(String studentId) =>
      _remote.watchAssessments(studentId);

  @override
  Future<Result<AssessmentOutcome>> assessStudentFees({
    required String studentId,
    required String schoolYear,
    required List<FeeItem> items,
    List<Installment> installments = const [],
    List<Discount> discounts = const [],
    List<Subsidy> subsidies = const [],
    String? sourceStructureId,
    String? sourceStructureName,
    String? remarks,
  }) async {
    try {
      final data = await _remote.assessStudentFees(
        studentId: studentId,
        schoolYear: schoolYear,
        items: items,
        installments: installments,
        discounts: discounts,
        subsidies: subsidies,
        sourceStructureId: sourceStructureId,
        sourceStructureName: sourceStructureName,
        remarks: remarks,
      );
      return Success(AssessmentOutcome(
        assessmentId: data['assessmentId'] as String,
        total: (data['total'] as num).toDouble(),
        newBalance: (data['balance'] as num).toDouble(),
      ));
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> voidAssessment({
    required String assessmentId,
    required String reason,
  }) async {
    try {
      await _remote.voidAssessment(assessmentId: assessmentId, reason: reason);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<RecordPaymentOutcome>> recordPayment({
    required String studentId,
    required double amount,
    required PaymentMethod method,
    required PaymentPurpose purpose,
    String? referenceNumber,
    int? officialReceiptNo,
  }) async {
    try {
      final data = await _remote.recordPayment(
        studentId: studentId,
        amount: amount,
        method: method.value,
        purpose: purpose.value,
        referenceNumber: referenceNumber,
        officialReceiptNo: officialReceiptNo,
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
  Stream<List<Payment>> watchAllPayments() => _remote.watchAllPayments();

  @override
  Stream<List<ReceiptBooklet>> watchReceiptBooklets() => _remote.watchReceiptBooklets();

  @override
  Future<Result<void>> saveReceiptBooklet({
    String? bookletId,
    required ReceiptBooklet booklet,
  }) async {
    try {
      await _remote.saveReceiptBooklet(bookletId: bookletId, booklet: booklet);
      return const Success(null);
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

  @override
  Stream<List<PaymentSubmission>> watchSubmissionsForStudent(String studentId) =>
      _remote.watchSubmissionsForStudent(studentId);

  @override
  Stream<List<PaymentSubmission>> watchSubmissions({bool pendingOnly = true}) =>
      _remote.watchSubmissions(pendingOnly: pendingOnly);

  @override
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
  }) async {
    try {
      await _remote.submitOnlinePayment(
        studentId: studentId,
        studentName: studentName,
        amount: amount,
        method: method.value,
        purpose: purpose.value,
        referenceNumber: referenceNumber,
        destinationLabel: destinationLabel,
        receiptUrl: receiptUrl,
        receiptFileName: receiptFileName,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> decideSubmission({
    required String submissionId,
    required bool approve,
    String? remarks,
  }) async {
    try {
      await _remote.decideSubmission(
        submissionId: submissionId,
        approve: approve,
        remarks: remarks,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Stream<PaymentSettings> watchPaymentSettings() => _remote.watchPaymentSettings();

  @override
  Future<Result<void>> updatePaymentSettings({
    String? qrCodeUrl,
    String? qrCodeFileName,
    String? accountName,
    String? accountNumber,
    String? instructions,
    List<BankAccount>? bankAccounts,
  }) async {
    try {
      // Only send what was provided, so saving the account details does
      // not wipe a previously uploaded QR (and vice versa).
      await _remote.updatePaymentSettings({
        if (qrCodeUrl != null) 'qrCodeUrl': qrCodeUrl,
        if (qrCodeFileName != null) 'qrCodeFileName': qrCodeFileName,
        if (accountName != null) 'accountName': accountName,
        if (accountNumber != null) 'accountNumber': accountNumber,
        if (instructions != null) 'instructions': instructions,
        // The whole list, when it is sent at all. Bank accounts are
        // edited as a set -- adding one, closing another -- and merging
        // a partial list would silently drop whichever the editor did
        // not happen to touch.
        if (bankAccounts != null)
          'bankAccounts': [for (final account in bankAccounts) account.toMap()],
      });
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
