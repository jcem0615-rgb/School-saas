import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../models/announcement_model.dart';
import '../models/approval_request_model.dart';
import '../models/expense_model.dart';
import '../models/meeting_model.dart';

/// Snapshot of who is performing the write, captured once per auth session
/// (see directorRemoteDataSourceProvider in the controller file, which
/// rebuilds this data source whenever the signed-in user changes).
class ActingUser {
  final String uid;
  final String schoolId;
  final String name;
  final String role;
  const ActingUser({required this.uid, required this.schoolId, required this.name, required this.role});
}

/// Most writes here go straight to Firestore from the client rather than
/// through a callable function -- these are ordinary CRUD operations
/// gated by firestore.rules (role + tenant checks) and automatically
/// captured by the generic `onAnyTenantDocWrite` audit trigger. Callables
/// are reserved for actions with real server-side business logic (auth,
/// billing) -- see docs/06-director-portal.md for the rationale.
class DirectorRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingUser _actingUser;

  const DirectorRemoteDataSource({
    required FirebaseFirestore firestore,
    required ActingUser actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  Map<String, dynamic> _baseFields() => {
        'schoolId': _actingUser.schoolId,
        'createdBy': _actingUser.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedBy': _actingUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'deletedAt': null,
        'deletedBy': null,
        'isDeleted': false,
      };

  /// Stamped on every edit. Deliberately does NOT touch createdBy --
  /// firestore.rules rejects any update that changes it, so an edit can
  /// never re-attribute authorship.
  Map<String, dynamic> _editFields() => {
        'updatedBy': _actingUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Deletion is a flag flip, never a document removal: every collection
  /// in firestore.rules sets `allow delete: if false`, so the only legal
  /// delete path is an update. Reads already filter on `isDeleted`, so
  /// flipping it is what makes a record disappear from the UI while
  /// leaving it recoverable and leaving the audit trail intact.
  Map<String, dynamic> _softDeleteFields() => {
        'isDeleted': true,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': _actingUser.uid,
        ..._editFields(),
      };

  // ---- Announcements ----

  Stream<List<AnnouncementModel>> watchAnnouncements() {
    return _firestore
        .collection(FirestorePaths.announcements(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AnnouncementModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createAnnouncement({
    required String title,
    required String body,
    required bool audienceAll,
    required List<String> audienceRoles,
    required List<String> audienceSections,
    required bool pinned,
  }) async {
    final ref = _firestore.collection(FirestorePaths.announcements(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'title': title,
      'body': body,
      'audience': {
        'all': audienceAll,
        'roles': audienceRoles,
        'sections': audienceSections,
      },
      'pinned': pinned,
      'createdByName': _actingUser.name,
      ..._baseFields(),
    });
  }

  Future<void> updateAnnouncement({
    required String announcementId,
    required String title,
    required String body,
    required bool audienceAll,
    required List<String> audienceRoles,
    required List<String> audienceSections,
    required bool pinned,
  }) async {
    await _firestore
        .collection(FirestorePaths.announcements(_actingUser.schoolId))
        .doc(announcementId)
        .update({
      'title': title,
      'body': body,
      'audience': {
        'all': audienceAll,
        'roles': audienceRoles,
        'sections': audienceSections,
      },
      'pinned': pinned,
      ..._editFields(),
    });
  }

  Future<void> softDeleteAnnouncement(String announcementId) async {
    await _firestore
        .collection(FirestorePaths.announcements(_actingUser.schoolId))
        .doc(announcementId)
        .update(_softDeleteFields());
  }

  // ---- Meetings ----

  Stream<List<MeetingModel>> watchMeetings() {
    return _firestore
        .collection(FirestorePaths.meetings(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('startTime', descending: false)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => MeetingModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createMeeting({
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) async {
    final ref = _firestore.collection(FirestorePaths.meetings(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'location': location,
      'attendeeRoles': attendeeRoles,
      'status': 'scheduled',
      'createdByName': _actingUser.name,
      ..._baseFields(),
    });
  }

  Future<void> updateMeeting({
    required String meetingId,
    required String title,
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    String? location,
    required List<String> attendeeRoles,
  }) async {
    await _firestore
        .collection(FirestorePaths.meetings(_actingUser.schoolId))
        .doc(meetingId)
        .update({
      'title': title,
      'description': description,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'location': location,
      'attendeeRoles': attendeeRoles,
      ..._editFields(),
    });
  }

  /// Distinct from [cancelMeeting]: cancelling keeps the meeting visible
  /// with a cancelled badge so attendees see it was called off, whereas
  /// deleting removes it from the list entirely. Both are updates.
  Future<void> softDeleteMeeting(String meetingId) async {
    await _firestore
        .collection(FirestorePaths.meetings(_actingUser.schoolId))
        .doc(meetingId)
        .update(_softDeleteFields());
  }

  Future<void> cancelMeeting(String meetingId) async {
    await _firestore
        .collection(FirestorePaths.meetings(_actingUser.schoolId))
        .doc(meetingId)
        .update({
      'status': 'cancelled',
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Approvals ----

  Stream<List<ApprovalRequestModel>> watchApprovals({String? statusFilter, String? requestedByUid}) {
    Query<Map<String, dynamic>> query = _firestore
        .collection(FirestorePaths.approvals(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false);
    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter);
    }
    if (requestedByUid != null) {
      query = query.where('createdBy', isEqualTo: requestedByUid);
    }
    return query
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ApprovalRequestModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createApprovalRequest({
    required String type,
    required String title,
    String? description,
    required Map<String, dynamic> details,
  }) async {
    final ref = _firestore.collection(FirestorePaths.approvals(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'type': type,
      'title': title,
      'description': description,
      'details': details,
      'requestedByName': _actingUser.name,
      'requestedByRole': _actingUser.role,
      'status': 'pending',
      'decidedByName': null,
      'decidedAt': null,
      'decisionRemarks': null,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': null,
      'deletedBy': null,
      'isDeleted': false,
    });
  }

  Future<void> decideApproval({
    required String approvalId,
    required bool approve,
    String? remarks,
  }) async {
    await _firestore
        .collection(FirestorePaths.approvals(_actingUser.schoolId))
        .doc(approvalId)
        .update({
      'status': approve ? 'approved' : 'rejected',
      'decidedByName': _actingUser.name,
      'decidedAt': FieldValue.serverTimestamp(),
      'decisionRemarks': remarks,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Expenses ----

  Stream<List<ExpenseModel>> watchExpenses() {
    return _firestore
        .collection(FirestorePaths.expenses(_actingUser.schoolId))
        .where('isDeleted', isEqualTo: false)
        .orderBy('date', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ExpenseModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> createExpense({
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) async {
    final ref = _firestore.collection(FirestorePaths.expenses(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'category': category,
      'description': description,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'receiptUrl': receiptUrl,
      'recordedByName': _actingUser.name,
      ..._baseFields(),
    });
  }

  Future<void> updateExpense({
    required String expenseId,
    required String category,
    required String description,
    required double amount,
    required DateTime date,
    String? receiptUrl,
  }) async {
    await _firestore
        .collection(FirestorePaths.expenses(_actingUser.schoolId))
        .doc(expenseId)
        .update({
      'category': category,
      'description': description,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'receiptUrl': receiptUrl,
      ..._editFields(),
    });
  }

  Future<void> softDeleteExpense(String expenseId) async {
    await _firestore
        .collection(FirestorePaths.expenses(_actingUser.schoolId))
        .doc(expenseId)
        .update(_softDeleteFields());
  }

  // ---- Dashboard aggregates ----
  // One-shot aggregation queries (count/sum) computed on demand -- see
  // DirectorDashboardSummary doc comment for why this doesn't need a
  // maintained rollup doc the way the Owner's platform-wide summary does.

  Future<Map<String, num>> fetchDashboardAggregates() async {
    final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    final todayEnd = todayStart.add(const Duration(days: 1));

    final attendanceCol = _firestore.collection(FirestorePaths.attendance(_actingUser.schoolId));
    final todayKey = todayStart.toIso8601String().substring(0, 10);

    final presentCountFuture = attendanceCol
        .where('date', isEqualTo: todayKey)
        .where('status', whereIn: ['present', 'late'])
        .count()
        .get();
    final totalCountFuture = attendanceCol.where('date', isEqualTo: todayKey).count().get();

    final paymentsSumFuture = _firestore
        .collection(FirestorePaths.payments(_actingUser.schoolId))
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .where('createdAt', isLessThan: Timestamp.fromDate(todayEnd))
        .where('status', isEqualTo: 'completed')
        .aggregate(sum('amount'))
        .get();

    final pendingApprovalsFuture = _firestore
        .collection(FirestorePaths.approvals(_actingUser.schoolId))
        .where('status', isEqualTo: 'pending')
        .count()
        .get();

    final upcomingMeetingsFuture = _firestore
        .collection(FirestorePaths.meetings(_actingUser.schoolId))
        .where('status', isEqualTo: 'scheduled')
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now()))
        .count()
        .get();

    final results = await Future.wait([
      presentCountFuture,
      totalCountFuture,
      paymentsSumFuture,
      pendingApprovalsFuture,
      upcomingMeetingsFuture,
    ]);

    return {
      'todayAttendancePresentCount': (results[0] as AggregateQuerySnapshot).count ?? 0,
      'todayAttendanceTotalCount': (results[1] as AggregateQuerySnapshot).count ?? 0,
      'todayPaymentsTotal': (results[2] as AggregateQuerySnapshot).getSum('amount') ?? 0,
      'pendingApprovalsCount': (results[3] as AggregateQuerySnapshot).count ?? 0,
      'upcomingMeetingsCount': (results[4] as AggregateQuerySnapshot).count ?? 0,
    };
  }
}
