import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/payables_remote_datasource.dart';
import '../../data/repositories_impl/payables_repository_impl.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/vendor.dart';
import '../../domain/repositories/payables_repository.dart';
import '../../domain/usecases/payables_usecases.dart';

final payablesRemoteDataSourceProvider = Provider<PayablesRemoteDataSource>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    throw StateError('PayablesRemoteDataSource requires a signed-in, school-scoped user.');
  }
  return PayablesRemoteDataSource(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(firebaseFunctionsProvider),
    actingUser: ActingBuyer(
      uid: user.uid,
      schoolId: user.schoolId!,
      name: user.fullName,
    ),
  );
});

final payablesRepositoryProvider = Provider<PayablesRepository>((ref) {
  return PayablesRepositoryImpl(ref.watch(payablesRemoteDataSourceProvider));
});

final vendorsProvider = StreamProvider.autoDispose<List<Vendor>>((ref) {
  return WatchVendorsUseCase(ref.watch(payablesRepositoryProvider))();
});

final billsProvider = StreamProvider.autoDispose<List<Bill>>((ref) {
  return WatchBillsUseCase(ref.watch(payablesRepositoryProvider))();
});

/// What the school owes, by how late it is.
///
/// Derived from the bills rather than stored, so a bill paid this
/// morning is off the report this morning. A stored ageing total is one
/// that drifts the first time a payment forgets to update it.
final payablesAgeingProvider = Provider.autoDispose<PayablesAgeing>((ref) {
  final bills = ref.watch(billsProvider).valueOrNull ?? const <Bill>[];
  return PayablesAgeing.from(bills);
});

/// The bills still owed, oldest due date first.
///
/// Due date rather than bill date: the question this list answers is
/// "what do I pay next", and that is decided by what is due soonest.
final outstandingBillsProvider = Provider.autoDispose<List<Bill>>((ref) {
  final bills = ref.watch(billsProvider).valueOrNull ?? const <Bill>[];
  return bills.where((b) => b.isOutstanding).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
});

final payablesActionControllerProvider =
    StateNotifierProvider.autoDispose<PayablesActionController, AsyncValue<void>>((ref) {
  final repo = ref.watch(payablesRepositoryProvider);
  return PayablesActionController(
    saveVendor: SaveVendorUseCase(repo),
    recordBill: RecordBillUseCase(repo),
    payBill: PayBillUseCase(repo),
    voidBill: VoidBillUseCase(repo),
  );
});

class PayablesActionController extends StateNotifier<AsyncValue<void>> {
  final SaveVendorUseCase _saveVendor;
  final RecordBillUseCase _recordBill;
  final PayBillUseCase _payBill;
  final VoidBillUseCase _voidBill;

  PayablesActionController({
    required SaveVendorUseCase saveVendor,
    required RecordBillUseCase recordBill,
    required PayBillUseCase payBill,
    required VoidBillUseCase voidBill,
  })  : _saveVendor = saveVendor,
        _recordBill = recordBill,
        _payBill = payBill,
        _voidBill = voidBill,
        super(const AsyncData(null));

  Future<bool> saveVendor(Vendor vendor) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _saveVendor(vendor));
  }

  Future<bool> recordBill({
    required String vendorId,
    required String billNumber,
    required DateTime billDate,
    required DateTime dueDate,
    required List<BillLine> lines,
    String? notes,
  }) async {
    if (mounted) state = const AsyncLoading();
    final result = await _recordBill(
      vendorId: vendorId,
      billNumber: billNumber,
      billDate: billDate,
      dueDate: dueDate,
      lines: lines,
      notes: notes,
    );
    return _settle(result.map((_) {}));
  }

  Future<bool> payBill({
    required Bill bill,
    required double amount,
    required String paidFromAccountCode,
    DateTime? date,
    String? reference,
  }) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _payBill(
      bill: bill,
      amount: amount,
      paidFromAccountCode: paidFromAccountCode,
      date: date,
      reference: reference,
    ));
  }

  Future<bool> voidBill({required Bill bill, required String reason}) async {
    if (mounted) state = const AsyncLoading();
    return _settle(await _voidBill(bill: bill, reason: reason));
  }

  bool _settle(Result<void> result) => switch (result) {
        Success() => () {
            if (mounted) state = const AsyncData(null);
            return true;
          }(),
        Error(:final failure) => () {
            if (mounted) state = AsyncError(failure.message, StackTrace.current);
            return false;
          }(),
      };
}
