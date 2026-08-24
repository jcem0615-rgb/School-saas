import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../registrar_portal/data/models/student_summary_model.dart';

class ParentRemoteDataSource {
  final FirebaseFirestore _firestore;
  final String _schoolId;

  const ParentRemoteDataSource({required FirebaseFirestore firestore, required String schoolId})
      : _firestore = firestore,
        _schoolId = schoolId;

  Stream<List<StudentSummaryModel>> watchChildren(List<String> linkedStudentIds) {
    if (linkedStudentIds.isEmpty) {
      // Firestore rejects an empty whereIn list outright -- short-circuit
      // rather than let that surface as a confusing runtime error.
      return Stream.value(const []);
    }
    // whereIn supports up to 30 values, comfortably above any realistic
    // number of children linked to one parent account.
    return _firestore
        .collection(FirestorePaths.students(_schoolId))
        .where(FieldPath.documentId, whereIn: linkedStudentIds)
        .snapshots()
        .map((snap) => snap.docs.map((d) => StudentSummaryModel.fromFirestore(d.id, d.data())).toList());
  }
}
