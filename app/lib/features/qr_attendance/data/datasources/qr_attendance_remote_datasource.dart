import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../models/attendance_record_model.dart';
import '../models/qr_scan_result_model.dart';

class QrAttendanceRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final String _schoolId;

  const QrAttendanceRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required String schoolId,
  })  : _firestore = firestore,
        _functions = functions,
        _schoolId = schoolId;

  Future<QrScanResultModel> scanQrCode({required String qrToken, String? location}) async {
    try {
      final callable = _functions.httpsCallable('markAttendance');
      final response = await callable.call({'qrToken': qrToken, 'location': location});
      return QrScanResultModel.fromCallableData(Map<String, dynamic>.from(response.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw ServerException(e.message ?? 'Failed to record attendance.');
    }
  }

  Stream<List<AttendanceRecordModel>> watchAttendanceHistory(String personId, {int limit = 60}) {
    return _firestore
        .collection(FirestorePaths.attendance(_schoolId))
        .where('personId', isEqualTo: personId)
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AttendanceRecordModel.fromFirestore(d.id, d.data())).toList());
  }
}
