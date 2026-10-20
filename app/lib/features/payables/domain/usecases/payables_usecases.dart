import '../../../../core/errors/failures.dart';
import '../../../../core/errors/result.dart';
import '../entities/bill.dart';
import '../entities/vendor.dart';
import '../repositories/payables_repository.dart';

class WatchVendorsUseCase {
  final PayablesRepository _repository;
  const WatchVendorsUseCase(this._repository);
  Stream<List<Vendor>> call() => _repository.watchVendors();
}

class WatchBillsUseCase {
  final PayablesRepository _repository;
  const WatchBillsUseCase(this._repository);
  Stream<List<Bill>> call() => _repository.watchBills();
}

class SaveVendorUseCase {
  final PayablesRepository _repository;
  const SaveVendorUseCase(this._repository);

  Future<Result<void>> call(Vendor vendor) {
    if (vendor.name.trim().isEmpty) {
      return Future.value(const Error(ValidationFailure('Give the supplier a name.')));
    }
    // Terms are days. A negative one would make a bill fall due before
    // it was issued, which the bill itself then refuses -- better to
    // refuse it here, where somebody can see the field they typed in.
    if (vendor.paymentTermsDays < 0) {
      return Future.value(const Error(
        ValidationFailure('Payment terms cannot be a negative number of days.'),
      ));
    }
    if (vendor.paymentTermsDays > 365) {
      return Future.value(const Error(
        ValidationFailure('Payment terms longer than a year are almost always a typo.'),
      ));
    }
    return _repository.saveVendor(vendor.copyWith(name: vendor.name.trim()));
  }
}

class RecordBillUseCase {
  final PayablesRepository _repository;
  const RecordBillUseCase(this._repository);

  Future<Result<String>> call({
    required String vendorId,
    required String billNumber,
    required DateTime billDate,
    required DateTime dueDate,
    required List<BillLine> lines,
    String? notes,
  }) {
    final problem = reasonBillCannotBeRecorded(
      vendorId: vendorId,
      billNumber: billNumber,
      billDate: billDate,
      dueDate: dueDate,
      lines: lines,
    );
    if (problem != null) return Future.value(Error(ValidationFailure(problem)));

    return _repository.recordBill(
      vendorId: vendorId,
      billNumber: billNumber.trim(),
      billDate: billDate,
      dueDate: dueDate,
      lines: lines,
      notes: notes?.trim().isEmpty ?? true ? null : notes!.trim(),
    );
  }
}

class PayBillUseCase {
  final PayablesRepository _repository;
  const PayBillUseCase(this._repository);

  Future<Result<void>> call({
    required Bill bill,
    required double amount,
    required String paidFromAccountCode,
    DateTime? date,
    String? reference,
  }) {
    final problem = reasonPaymentCannotBeMade(
      bill: bill,
      amount: amount,
      paidFromAccountCode: paidFromAccountCode,
    );
    if (problem != null) return Future.value(Error(ValidationFailure(problem)));

    return _repository.payBill(
      billId: bill.id,
      amount: amount,
      paidFromAccountCode: paidFromAccountCode,
      date: date,
      reference: reference?.trim().isEmpty ?? true ? null : reference!.trim(),
    );
  }
}

/// Voids a bill that should never have been recorded.
///
/// Not a deletion. The bill stays, marked void with a reason, and the
/// liability is reversed by its own entry.
class VoidBillUseCase {
  final PayablesRepository _repository;
  const VoidBillUseCase(this._repository);

  Future<Result<void>> call({required Bill bill, required String reason}) {
    final why = reason.trim();
    if (why.length < 4) {
      return Future.value(const Error(ValidationFailure('Say why it is being voided.')));
    }
    if (bill.isVoid) {
      return Future.value(const Error(ValidationFailure('That bill is already void.')));
    }
    // Once money has gone out, the cash really did leave. Pretending the
    // bill never existed would leave a payment pointing at nothing.
    if (bill.amountPaid > 0) {
      return Future.value(const Error(ValidationFailure(
        'Money has already been paid against this bill, so it cannot be '
        'voided. Record a credit from the supplier instead.',
      )));
    }
    return _repository.voidBill(billId: bill.id, reason: why);
  }
}
