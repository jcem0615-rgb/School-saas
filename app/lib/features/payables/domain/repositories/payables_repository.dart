import '../../../../core/errors/result.dart';
import '../entities/bill.dart';
import '../entities/vendor.dart';

abstract class PayablesRepository {
  Stream<List<Vendor>> watchVendors();

  /// Every bill, newest first.
  ///
  /// Not filtered to the outstanding ones: a school looks up what it
  /// paid last March as often as what it owes today, and the ageing
  /// report needs the paid ones to leave them off itself.
  Stream<List<Bill>> watchBills();

  Future<Result<void>> saveVendor(Vendor vendor);

  /// Records the bill and the liability it creates, together.
  Future<Result<String>> recordBill({
    required String vendorId,
    required String billNumber,
    required DateTime billDate,
    required DateTime dueDate,
    required List<BillLine> lines,
    String? notes,
  });

  Future<Result<void>> payBill({
    required String billId,
    required double amount,
    required String paidFromAccountCode,
    DateTime? date,
    String? reference,
  });

  Future<Result<void>> voidBill({
    required String billId,
    required String reason,
  });
}
