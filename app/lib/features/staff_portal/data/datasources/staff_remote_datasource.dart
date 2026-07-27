import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../models/checklist_item_model.dart';
import '../models/daily_report_model.dart';

class ActingStaff {
  final String uid;
  final String schoolId;
  final String name;
  const ActingStaff({required this.uid, required this.schoolId, required this.name});
}

class StaffRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingStaff _actingUser;

  const StaffRemoteDataSource({required FirebaseFirestore firestore, required ActingStaff actingUser})
      : _firestore = firestore,
        _actingUser = actingUser;

  Stream<List<ChecklistItemModel>> watchMyChecklist(String date) {
    return _firestore
        .collection(FirestorePaths.checklistItems(_actingUser.schoolId))
        .where('staffId', isEqualTo: _actingUser.uid)
        .where('date', isEqualTo: date)
        .where('isDeleted', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) => ChecklistItemModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> addChecklistItem({required String task, required String date}) async {
    final ref = _firestore.collection(FirestorePaths.checklistItems(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'staffId': _actingUser.uid,
      'staffName': _actingUser.name,
      'task': task,
      'date': date,
      'completed': false,
      'completedAt': null,
      'notes': null,
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

  Future<void> toggleChecklistItem({required String itemId, required bool completed}) async {
    await _firestore.doc('${FirestorePaths.checklistItems(_actingUser.schoolId)}/$itemId').update({
      'completed': completed,
      'completedAt': completed ? FieldValue.serverTimestamp() : null,
      'updatedBy': _actingUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<DailyReportModel>> watchMyDailyReports() {
    return _firestore
        .collection(FirestorePaths.dailyReports(_actingUser.schoolId))
        .where('staffId', isEqualTo: _actingUser.uid)
        .where('isDeleted', isEqualTo: false)
        .orderBy('submittedAt', descending: true)
        .limit(90)
        .snapshots()
        .map((snap) => snap.docs.map((d) => DailyReportModel.fromFirestore(d.id, d.data())).toList());
  }

  Future<void> submitDailyReport({required String date, required String content}) async {
    final ref = _firestore.collection(FirestorePaths.dailyReports(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'staffId': _actingUser.uid,
      'staffName': _actingUser.name,
      'date': date,
      'content': content,
      'submittedAt': FieldValue.serverTimestamp(),
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
}
