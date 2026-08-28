import '../../../../core/constants/education_level.dart';
import '../../../../core/errors/result.dart';
import '../entities/invoice.dart';
import '../entities/revenue_summary.dart';
import '../entities/school_summary.dart';

abstract class OwnerRepository {
  Stream<List<SchoolSummary>> watchSchools();

  /// Adds a school to the platform. Owner only, enforced server-side.
  ///
  /// A school is three documents -- the platform record, its subscription
  /// and the tenant-side profile -- written together, so this returns the
  /// new school's id rather than void: it is the id every account in that
  /// school will be scoped to, and the caller needs it to provision the
  /// Director next.
  Future<Result<String>> createSchool({
    required String name,
    required double billingRatePerStudent,
    // Which divisions the school runs. Required, and required to be
    // non-empty: a school with no divisions on record shows a
    // registration form that cannot say what a student is enrolling into.
    required Set<EducationLevel> educationLevels,
    String? schoolId,
    String? addressLine,
    String? contactEmail,
    String? contactPhone,
  });

  Stream<RevenueSummary> watchRevenueSummary();

  Stream<List<Invoice>> watchInvoices(String schoolId);

  /// Pauses a school: sets subscription status to suspended immediately
  /// (bypassing grace period), used for manual intervention e.g. contract
  /// violation, rather than automatic non-payment suspension.
  Future<Result<void>> pauseSchool({required String schoolId, required String reason});

  /// Reactivates a paused/suspended school immediately. Per spec, this
  /// must take effect right away -- no waiting for a billing cycle.
  Future<Result<void>> resumeSchool({required String schoolId});

  /// Manually records a payment received outside any automated gateway
  /// (cash/GCash/bank transfer handed to the Owner directly), applying it
  /// to the given invoice and reactivating the school if it was suspended
  /// for non-payment.
  Future<Result<void>> recordManualPayment({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required PaymentMethod method,
    String? referenceNumber,
  });
}
