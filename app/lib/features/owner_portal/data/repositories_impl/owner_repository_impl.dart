import '../../../../core/errors/app_exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/revenue_summary.dart';
import '../../domain/entities/school_summary.dart';
import '../../domain/repositories/owner_repository.dart';
import '../datasources/owner_remote_datasource.dart';

class OwnerRepositoryImpl implements OwnerRepository {
  final OwnerRemoteDataSource _remote;
  const OwnerRepositoryImpl(this._remote);

  @override
  Stream<List<SchoolSummary>> watchSchools() => _remote.watchSchools();

  @override
  Stream<RevenueSummary> watchRevenueSummary() => _remote.watchRevenueSummary();

  @override
  Stream<List<Invoice>> watchInvoices(String schoolId) => _remote.watchInvoices(schoolId);

  @override
  Future<Result<String>> createSchool({
    required String name,
    required double billingRatePerStudent,
    String? schoolId,
    String? addressLine,
    String? contactEmail,
    String? contactPhone,
  }) async {
    try {
      final id = await _remote.createSchool(
        name: name,
        billingRatePerStudent: billingRatePerStudent,
        schoolId: schoolId,
        addressLine: addressLine,
        contactEmail: contactEmail,
        contactPhone: contactPhone,
      );
      return Success(id);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> pauseSchool({required String schoolId, required String reason}) async {
    try {
      await _remote.pauseSchool(schoolId: schoolId, reason: reason);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> resumeSchool({required String schoolId}) async {
    try {
      await _remote.resumeSchool(schoolId: schoolId);
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }

  @override
  Future<Result<void>> recordManualPayment({
    required String schoolId,
    required String invoiceId,
    required double amount,
    required PaymentMethod method,
    String? referenceNumber,
  }) async {
    try {
      await _remote.recordManualPayment(
        schoolId: schoolId,
        invoiceId: invoiceId,
        amount: amount,
        method: method.value,
        referenceNumber: referenceNumber,
      );
      return const Success(null);
    } on ServerException catch (e) {
      return Error(ServerFailure(e.message));
    } catch (_) {
      return const Error(UnknownFailure());
    }
  }
}
