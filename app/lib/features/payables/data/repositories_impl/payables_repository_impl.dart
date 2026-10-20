import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/vendor.dart';
import '../../domain/repositories/payables_repository.dart';
import '../datasources/payables_remote_datasource.dart';

class PayablesRepositoryImpl implements PayablesRepository {
  final PayablesRemoteDataSource _remote;
  const PayablesRepositoryImpl(this._remote);

  @override
  Stream<List<Vendor>> watchVendors() => _remote.watchVendors();

  @override
  Stream<List<Bill>> watchBills() => _remote.watchBills();

  @override
  Future<Result<void>> saveVendor(Vendor vendor) async {
    final result = await _guard(() async {
      await _remote.saveVendor(vendor);
      return '';
    }, 'The supplier could not be saved.');
    return result.map((_) {});
  }

  @override
  Future<Result<String>> recordBill({
    required String vendorId,
    required String billNumber,
    required DateTime billDate,
    required DateTime dueDate,
    required List<BillLine> lines,
    String? notes,
  }) =>
      _guard(
        () => _remote.recordBill(
          vendorId: vendorId,
          billNumber: billNumber,
          billDate: billDate,
          dueDate: dueDate,
          lines: lines,
          notes: notes,
        ),
        'The bill could not be recorded.',
      );

  @override
  Future<Result<void>> payBill({
    required String billId,
    required double amount,
    required String paidFromAccountCode,
    DateTime? date,
    String? reference,
  }) async {
    final result = await _guard(() async {
      await _remote.payBill(
        billId: billId,
        amount: amount,
        paidFromAccountCode: paidFromAccountCode,
        date: date,
        reference: reference,
      );
      return '';
    }, 'The payment could not be recorded.');
    return result.map((_) {});
  }

  @override
  Future<Result<void>> voidBill({
    required String billId,
    required String reason,
  }) async {
    final result = await _guard(() async {
      await _remote.voidBill(billId: billId, reason: reason);
      return '';
    }, 'The bill could not be voided.');
    return result.map((_) {});
  }

  /// One place that turns a thrown error into a sentence.
  ///
  /// `already-exists` is the one worth singling out: it is the duplicate
  /// invoice check, and it is the most useful refusal in this module --
  /// entering the same bill twice is how a supplier gets paid twice.
  Future<Result<String>> _guard(
    Future<String> Function() run,
    String fallback,
  ) async {
    try {
      return Success(await run());
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'Only the Director or an Admin can work the payables ledger.',
        ));
      }
      return Error(ValidationFailure(e.message ?? fallback));
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'This account cannot read or change what the school owes.',
        ));
      }
      return Error(ServerFailure(e.message ?? fallback));
    } catch (_) {
      return Error(UnknownFailure(fallback));
    }
  }
}
