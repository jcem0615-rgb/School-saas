import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../domain/entities/student_document.dart';
import '../models/student_document_model.dart';

class ActingFiler {
  final String uid;
  final String schoolId;
  final String name;
  const ActingFiler({required this.uid, required this.schoolId, required this.name});
}

/// Reads and writes the student folders.
///
/// Ordinary Firestore writes rather than callables, for the same reason
/// `documentReleases` is: nothing here is a figure the server owns.
/// firestore.rules pins `filedBy` to the caller, allows an update only
/// when it is an archive, and refuses every delete -- which is the whole
/// of what has to be enforced about a folder.
class DocumentsRemoteDataSource {
  final FirebaseFirestore _firestore;
  final ActingFiler _actingUser;

  const DocumentsRemoteDataSource({
    required FirebaseFirestore firestore,
    required ActingFiler actingUser,
  })  : _firestore = firestore,
        _actingUser = actingUser;

  /// One student's folder, newest first.
  ///
  /// Archived rows are not filtered out here. The office asks what used
  /// to be in the folder as well as what is, and a second query to answer
  /// that would double the reads on a screen that is already open.
  Stream<List<StudentDocumentModel>> watchStudentDocuments(String studentId) {
    return _firestore
        .collection(FirestorePaths.studentDocuments(_actingUser.schoolId))
        .where('studentId', isEqualTo: studentId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('filedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => StudentDocumentModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  /// Records a paper whose bytes are already in Storage.
  ///
  /// `filedAt` comes from the server clock. A device with the wrong date
  /// would otherwise file a birth certificate under a day it was not
  /// received, and "when did we get it" is most of what this row is for.
  Future<void> fileDocument({
    required String studentId,
    required String studentName,
    required DocumentKind kind,
    required DocumentOrigin origin,
    required String title,
    required String fileName,
    required String url,
    required String contentType,
    required int sizeBytes,
    String? note,
    String? releaseId,
  }) async {
    final ref =
        _firestore.collection(FirestorePaths.studentDocuments(_actingUser.schoolId)).doc();
    await ref.set({
      'id': ref.id,
      'studentId': studentId,
      'studentName': studentName,
      'kind': kind.value,
      'origin': origin.value,
      'title': title,
      'fileName': fileName,
      'url': url,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'note': note,
      'releaseId': releaseId,
      'filedByName': _actingUser.name,
      'filedBy': _actingUser.uid,
      'filedAt': FieldValue.serverTimestamp(),
      // Written as nulls rather than left absent so the archive update
      // changes fields that already exist -- the rule checks which keys
      // the diff touches, and a key that appears from nowhere reads as a
      // different edit.
      'archivedAt': null,
      'archivedByName': null,
      'archiveReason': null,
      'schoolId': _actingUser.schoolId,
      'createdBy': _actingUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    });
  }

  /// Withdraws a paper. Three fields and nothing else, which is exactly
  /// what the rule permits -- an update that touched the url or the
  /// student would be a different document wearing this one's history.
  Future<void> archiveDocument({
    required String documentId,
    required String reason,
  }) async {
    await _firestore
        .doc(FirestorePaths.studentDocumentDoc(_actingUser.schoolId, documentId))
        .update({
      'archivedAt': FieldValue.serverTimestamp(),
      'archivedByName': _actingUser.name,
      'archiveReason': reason,
    });
  }
}
