import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/constants/user_roles.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../domain/entities/school_totals.dart';

/// Aggregation queries, not document reads.
///
/// Firestore's `count()` and `sum()` are answered by the index without
/// returning a single document, so this costs a few reads regardless of
/// whether the school has ninety students or nine thousand. That is the
/// whole reason this is not built on the roster stream: the unbounded
/// roster is the right tool for a submission sheet and the wrong one for
/// a figure on a dashboard somebody opens twenty times a day.
class SchoolTotalsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;
  final String _uid;
  final UserRole _role;

  const SchoolTotalsRemoteDataSource({
    required FirebaseFirestore firestore,
    required String schoolId,
    required String uid,
    required UserRole role,
  })  : _firestore = firestore,
        _schoolId = schoolId,
        _uid = uid,
        _role = role;

  /// The roles allowed to see what a family owes.
  ///
  /// The same list that may collect a payment. A Principal is division
  /// oversight and is deliberately absent: financial data stays with
  /// Director, Admin and Registrar, which is the boundary
  /// docs/16-principal-role.md draws and firestore.rules enforces. Asking
  /// anyway would not leak anything -- the read would simply be refused
  /// -- but it would turn a designed boundary into an error message.
  static const _moneyRoles = {UserRole.director, UserRole.admin, UserRole.registrar};

  Future<SchoolTotals> fetch() async {
    try {
      final division = await _myDivision();
      final students = _firestore.collection(FirestorePaths.students(_schoolId));

      // Every query carries the division when the reader has one.
      // Without it the rules refuse an aggregate that would span
      // divisions -- correctly -- and the card would show an error where
      // a scoped Principal expects their own head count.
      //
      // isDeleted is on every one of them for the same reason every other
      // read in the app carries it: a soft-deleted student is off the
      // roll, and counting them would inflate the head count the school
      // is billed on.
      Query<Map<String, dynamic>> scoped(Query<Map<String, dynamic>> q) {
        final base = q.where('isDeleted', isEqualTo: false);
        return division == null
            ? base
            : base.where('educationLevel', isEqualTo: division.value);
      }

      final activeFuture =
          scoped(students.where('status', isEqualTo: 'enrolled')).count().get();

      if (!_moneyRoles.contains(_role)) {
        final active = await activeFuture;
        return SchoolTotals(
          activeStudents: active.count ?? 0,
          division: division,
        );
      }

      // Positive balances only. A credit is money held, not owed, and
      // summing the two together lets one family's overpayment cancel
      // another's arrears.
      final owing = scoped(students.where('balance', isGreaterThan: 0));
      final outstandingFuture = owing.aggregate(sum('balance')).get();
      final owingCountFuture = owing.count().get();

      // Every row, not the completed ones. A refund is its own negative
      // row and the payment it reverses keeps its positive one, so the
      // pair nets itself off; filtering by status would report a month's
      // take without the money handed back out of it.
      //
      // Deliberately the same two fields the existing payments index
      // already covers -- a query that needs an index nobody deployed is
      // one that works in the emulator and fails at the counter.
      final monthStart = _startOfThisMonth();
      final collectedFuture = _firestore
          .collection(FirestorePaths.payments(_schoolId))
          .where('isDeleted', isEqualTo: false)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .aggregate(sum('amount'))
          .get();

      final results = await Future.wait([
        activeFuture,
        outstandingFuture,
        owingCountFuture,
        collectedFuture,
      ]);

      return SchoolTotals(
        activeStudents: (results[0] as AggregateQuerySnapshot).count ?? 0,
        division: division,
        outstanding: (results[1] as AggregateQuerySnapshot).getSum('balance') ?? 0,
        studentsOwing: (results[2] as AggregateQuerySnapshot).count ?? 0,
        collectedThisMonth: (results[3] as AggregateQuerySnapshot).getSum('amount') ?? 0,
      );
    } on FirebaseException catch (e) {
      throw ServerException(e.message ?? 'Could not read the school totals.');
    }
  }

  /// The signed-in account's own division, or null when they are
  /// school-wide.
  ///
  /// Read from their own user document because the app does not carry it:
  /// `assignedDivision` reaches firestore.rules as a custom claim, which
  /// the client never sees. One document read, and the account's own, so
  /// there is no rule it could fall foul of.
  Future<EducationLevel?> _myDivision() async {
    final snap =
        await _firestore.doc(FirestorePaths.userDoc(_schoolId, _uid)).get();
    final info = snap.data()?['employeeInfo'] as Map<String, dynamic>?;
    final value = info?['assignedDivision'] as String?;
    return value == null ? null : EducationLevel.tryFromString(value);
  }

  static DateTime _startOfThisMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }
}
