import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/result.dart';
import '../../payments/domain/entities/payment.dart';
import '../domain/entities/cashier_shift.dart';

/// What a close returned: the figures the server worked out, so the
/// screen can show the reckoning rather than guess at it.
class ShiftClosing {
  final double expectedAmount;
  final double variance;
  final double cashCollected;
  final double cashRefunded;
  final int receiptCount;

  const ShiftClosing({
    required this.expectedAmount,
    required this.variance,
    required this.cashCollected,
    required this.cashRefunded,
    required this.receiptCount,
  });
}

abstract class CashieringRepository {
  /// This cashier's drawers, newest first.
  Stream<List<CashierShift>> watchMyShifts();

  /// Every cashier's, for the office.
  Stream<List<CashierShift>> watchAllShifts();

  /// What the open drawer has taken so far.
  ///
  /// Read live rather than at close, because a cashier counting up wants
  /// to know what the drawer should hold before they start counting --
  /// and a figure that only appears afterwards is one they cannot check
  /// themselves against.
  Stream<ShiftReckoning> watchReckoning(CashierShift shift);

  Future<Result<String>> openShift({required double openingFloat, String? notes});

  Future<Result<ShiftClosing>> closeShift({
    required String shiftId,
    required double countedAmount,
    String? varianceNote,
  });
}

class ActingCashier {
  final String uid;
  final String schoolId;
  final String name;
  const ActingCashier({required this.uid, required this.schoolId, required this.name});
}

class CashierShiftModel extends CashierShift {
  const CashierShiftModel({
    required super.id,
    required super.cashierUid,
    required super.cashierName,
    required super.openedAt,
    required super.openingFloat,
    super.closedAt,
    super.countedAmount,
    super.expectedAmount,
    super.varianceNote,
    super.closedByName,
    super.journalEntryId,
    super.notes,
  });

  factory CashierShiftModel.fromFirestore(String id, Map<String, dynamic> data) =>
      CashierShiftModel(
        id: id,
        cashierUid: data['cashierUid'] as String? ?? '',
        cashierName: data['cashierName'] as String? ?? 'Unknown',
        // Written from the server clock, so null in the local echo of a
        // document that has not round-tripped yet.
        openedAt: (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        openingFloat: (data['openingFloat'] as num?)?.toDouble() ?? 0,
        closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
        countedAmount: (data['countedAmount'] as num?)?.toDouble(),
        expectedAmount: (data['expectedAmount'] as num?)?.toDouble(),
        varianceNote: data['varianceNote'] as String?,
        closedByName: data['closedByName'] as String?,
        journalEntryId: data['journalEntryId'] as String?,
        notes: data['notes'] as String?,
      );
}

class CashieringRepositoryImpl implements CashieringRepository {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingCashier _actingUser;

  const CashieringRepositoryImpl({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingCashier actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  Stream<List<CashierShift>> _shifts(Query<Map<String, dynamic>> query) =>
      query.snapshots().map((snap) => snap.docs
          .map((d) => CashierShiftModel.fromFirestore(d.id, d.data()))
          .toList()
        ..sort((a, b) => b.openedAt.compareTo(a.openedAt)));

  @override
  Stream<List<CashierShift>> watchMyShifts() => _shifts(
        _firestore
            .collection(FirestorePaths.cashierShifts(_actingUser.schoolId))
            .where('cashierUid', isEqualTo: _actingUser.uid),
      );

  @override
  Stream<List<CashierShift>> watchAllShifts() => _shifts(
        _firestore.collection(FirestorePaths.cashierShifts(_actingUser.schoolId)),
      );

  @override
  Stream<ShiftReckoning> watchReckoning(CashierShift shift) {
    // The same window the server reckons over at close, so what a
    // cashier sees while counting is what they will be held to.
    return _firestore
        .collection(FirestorePaths.payments(_actingUser.schoolId))
        .where('collectedBy', isEqualTo: shift.cashierUid)
        .where('method', isEqualTo: PaymentMethod.cash.value)
        .where('isDeleted', isEqualTo: false)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(shift.openedAt))
        .snapshots()
        .map((snap) {
      var collected = 0.0;
      var refunded = 0.0;
      var count = 0;
      for (final doc in snap.docs) {
        final at = (doc.data()['createdAt'] as Timestamp?)?.toDate();
        // A closed shift's window has an end; the query cannot carry an
        // upper bound and a live lower bound at once without a second
        // index, and this list is one cashier's day.
        if (at != null && !shift.holds(at)) continue;
        final amount = (doc.data()['amount'] as num?)?.toDouble() ?? 0;
        if (amount >= 0) {
          collected += amount;
        } else {
          refunded += amount.abs();
        }
        count++;
      }
      return ShiftReckoning(
        openingFloat: shift.openingFloat,
        cashCollected: collected,
        cashRefunded: refunded,
        receiptCount: count,
      );
    });
  }

  @override
  Future<Result<String>> openShift({
    required double openingFloat,
    String? notes,
  }) =>
      _guard(() async {
        final result = await _functions
            .httpsCallable('openCashierShift')
            .call<Map<String, dynamic>>({
          'schoolId': _actingUser.schoolId,
          'openingFloat': openingFloat,
          if (notes != null) 'notes': notes,
        });
        return result.data['shiftId'] as String? ?? '';
      }, 'The drawer could not be opened.');

  @override
  Future<Result<ShiftClosing>> closeShift({
    required String shiftId,
    required double countedAmount,
    String? varianceNote,
  }) async {
    final result = await _guard(() async {
      final call = await _functions
          .httpsCallable('closeCashierShift')
          .call<Map<String, dynamic>>({
        'schoolId': _actingUser.schoolId,
        'shiftId': shiftId,
        'countedAmount': countedAmount,
        if (varianceNote != null) 'varianceNote': varianceNote,
      });
      return call.data;
    }, 'The drawer could not be closed.');

    return switch (result) {
      Success(:final value) => Success(ShiftClosing(
          expectedAmount: (value['expectedAmount'] as num?)?.toDouble() ?? 0,
          variance: (value['variance'] as num?)?.toDouble() ?? 0,
          cashCollected: (value['cashCollected'] as num?)?.toDouble() ?? 0,
          cashRefunded: (value['cashRefunded'] as num?)?.toDouble() ?? 0,
          receiptCount: (value['receiptCount'] as num?)?.toInt() ?? 0,
        )),
      Error(:final failure) => Error(failure),
    };
  }

  Future<Result<T>> _guard<T>(Future<T> Function() run, String fallback) async {
    try {
      return Success(await run());
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'permission-denied') {
        return Error(PermissionFailure(e.message ?? 'Only a cashier can do that.'));
      }
      // `failed-precondition` is a drawer already open or already
      // closed, and the message names which. Passed through rather than
      // flattened: it is the most useful thing the server can say here.
      return Error(ValidationFailure(e.message ?? fallback));
    } on FirebaseException catch (e) {
      return Error(ServerFailure(e.message ?? fallback));
    } catch (_) {
      return Error(UnknownFailure(fallback));
    }
  }
}
