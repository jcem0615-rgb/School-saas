import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/result.dart';
import '../domain/entities/budget.dart';

/// Reads and writes the plan.
///
/// A plain Firestore write, unlike a bill or a journal entry. A budget is
/// a plan, not a record of money that moved: nothing has to balance and
/// nothing has to commit alongside anything else, so there is nothing a
/// callable would add except a round trip.
abstract class BudgetsRepository {
  Stream<List<Budget>> watchBudgets(String schoolYear);

  /// Sets one account's allowance. Idempotent by construction: the
  /// document id is the year and the account.
  Future<Result<void>> setBudget(Budget budget);
}

class ActingPlanner {
  final String uid;
  final String schoolId;
  final String name;
  const ActingPlanner({required this.uid, required this.schoolId, required this.name});
}

class BudgetModel extends Budget {
  const BudgetModel({
    required super.schoolYear,
    required super.accountCode,
    required super.accountName,
    required super.amount,
    required super.setByName,
    required super.setAt,
    super.note,
  });

  factory BudgetModel.fromFirestore(Map<String, dynamic> data) => BudgetModel(
        schoolYear: data['schoolYear'] as String? ?? '',
        accountCode: data['accountCode'] as String? ?? '',
        accountName: data['accountName'] as String? ?? 'Unknown account',
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        note: data['note'] as String?,
        setByName: data['setByName'] as String? ?? 'Unknown',
        // Written from the server clock, so null in the local echo of a
        // document that has not round-tripped yet.
        setAt: (data['setAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

class BudgetsRepositoryImpl implements BudgetsRepository {
  final FirebaseFirestore _firestore;
  final ActingPlanner _actingUser;

  const BudgetsRepositoryImpl({
    required FirebaseFirestore firestore,
    required ActingPlanner actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  @override
  Stream<List<Budget>> watchBudgets(String schoolYear) => _firestore
      .collection(FirestorePaths.budgets(_actingUser.schoolId))
      .where('schoolYear', isEqualTo: schoolYear)
      .snapshots()
      .map((snap) => snap.docs.map((d) => BudgetModel.fromFirestore(d.data())).toList());

  @override
  Future<Result<void>> setBudget(Budget budget) async {
    try {
      await _firestore
          .doc(FirestorePaths.budgetDoc(
            _actingUser.schoolId,
            budget.schoolYear,
            budget.accountCode,
          ))
          .set({
        'schoolYear': budget.schoolYear,
        'accountCode': budget.accountCode,
        'accountName': budget.accountName,
        'amount': budget.amount,
        'note': budget.note,
        'schoolId': _actingUser.schoolId,
        'setBy': _actingUser.uid,
        'setByName': _actingUser.name,
        'setAt': FieldValue.serverTimestamp(),
      });
      return const Success(null);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return const Error(PermissionFailure(
          'Only the Director or an Admin can set a budget.',
        ));
      }
      return Error(ServerFailure(e.message ?? 'The budget could not be saved.'));
    } catch (_) {
      return const Error(UnknownFailure('The budget could not be saved.'));
    }
  }
}
