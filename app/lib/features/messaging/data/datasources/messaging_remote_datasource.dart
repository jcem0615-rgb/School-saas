import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../domain/entities/conversation.dart';
import '../models/conversation_model.dart';

/// Who is acting, stamped onto every message they send.
class ActingMessenger {
  final String uid;
  final String schoolId;
  final String name;
  final String role;
  const ActingMessenger({
    required this.uid,
    required this.schoolId,
    required this.name,
    required this.role,
  });
}

class MessagingRemoteDataSource {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final ActingMessenger _actingUser;

  /// A thread nobody scrolls past. Long threads are read from the bottom
  /// anyway, and an unbounded subscription on a two-year conversation is
  /// a screen that takes a second to open every time.
  static const messagePageSize = 200;

  const MessagingRemoteDataSource({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required ActingMessenger actingUser,
  })  : _firestore = firestore,
        _functions = functions,
        _actingUser = actingUser;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection(FirestorePaths.conversations(_actingUser.schoolId));

  /// Filtered to the signed-in account, which is also what makes the read
  /// rule satisfiable per document: an unfiltered query would return a
  /// conversation this person is not in, and the whole query would fail.
  ///
  /// Ordered again in memory. Firestore sorts nulls before everything
  /// else, so a `lastMessageAt DESC` query puts a thread nobody has
  /// written in yet at the very bottom -- under conversations from last
  /// term. A parent who has just opened one to ask a question would have
  /// to scroll past every old thread to find it. [Conversation.sortedAt]
  /// falls back to when the thread was opened, which is the answer
  /// somebody expects.
  Stream<List<Conversation>> watchMyConversations() {
    return _conversations
        .where('participantUids', arrayContains: _actingUser.uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) {
      final conversations = snap.docs
          .map((d) => ConversationModel.fromFirestore(d.id, d.data()))
          .toList();
      conversations.sort((a, b) {
        final left = a.sortedAt;
        final right = b.sortedAt;
        // A thread with no date at all sorts last rather than first: it
        // is a document mid-write, not the newest thing in the list.
        if (left == null) return right == null ? 0 : 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
      return conversations;
    });
  }

  Stream<List<Message>> watchMessages(String conversationId) {
    return _firestore
        .collection(
            FirestorePaths.messages(_actingUser.schoolId, conversationId))
        .orderBy('sentAt', descending: true)
        .limit(messagePageSize)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => MessageModel.fromFirestore(d.id, d.data()))
            .toList());
  }

  Future<String> startConversation({
    required String studentId,
    required String otherUid,
  }) async {
    try {
      final result = await _functions
          .httpsCallable('startConversation')
          .call<Map<String, dynamic>>({
        'schoolId': _actingUser.schoolId,
        'studentId': studentId,
        'otherUid': otherUid,
      });
      return result.data['conversationId'] as String;
    } on FirebaseFunctionsException catch (e) {
      // The server's own message is worth showing: "that teacher does
      // not teach this student's class" is something a parent can act
      // on, where "something went wrong" is not.
      throw ServerException(e.message ?? 'That conversation could not be opened.');
    }
  }

  Future<void> send({required String conversationId, required String text}) async {
    final ref = _firestore
        .collection(FirestorePaths.messages(_actingUser.schoolId, conversationId))
        .doc();
    await ref.set({
      'id': ref.id,
      // Pinned to the caller by the rules as well as here, so nobody
      // puts words in the other person's mouth.
      'senderUid': _actingUser.uid,
      'senderName': _actingUser.name,
      'senderRole': _actingUser.role,
      'text': text,
      'sentAt': FieldValue.serverTimestamp(),
    });
  }

  /// Clears this account's own count and leaves the other person's as it
  /// stands -- which is what the rules require, and what stops "I read
  /// it" from becoming "you read it".
  Future<void> markRead(String conversationId) async {
    final ref = _conversations.doc(conversationId);
    final snap = await ref.get();
    final data = snap.data();
    if (data == null) return;

    final unread = <String, int>{
      for (final entry in (data['unread'] as Map<dynamic, dynamic>? ?? const {}).entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toInt(),
    };
    if ((unread[_actingUser.uid] ?? 0) == 0) return;

    unread[_actingUser.uid] = 0;
    await ref.update({'unread': unread});
  }

  // --- Who this person may write to -------------------------------------
  //
  // These were queried from the New message sheet's own providers, which
  // made that screen the one place in the app reaching past the
  // repositories into Firestore. It could not open in the demo, where
  // there is no Firebase at all, and nothing had ever tested it.

  /// The sections the signed-in teacher is assigned to.
  ///
  /// From their assignments rather than the timetable, because a teacher
  /// can be adviser to a class they have no timetabled block with -- and
  /// that is exactly the class whose parents they most need to reach.
  Future<List<String>> mySections() async {
    final snap = await _firestore
        .collection(FirestorePaths.teacherAssignments(_actingUser.schoolId))
        .where('teacherId', isEqualTo: _actingUser.uid)
        .get();

    return <String>{
      for (final doc in snap.docs)
        if (doc.data()['section'] case final String section) section,
    }.toList()
      ..sort();
  }

  /// The enrolled students in one section.
  Future<List<MessageablePerson>> studentsInSection(String section) async {
    final snap = await _firestore
        .collection(FirestorePaths.students(_actingUser.schoolId))
        .where('section', isEqualTo: section)
        .where('status', isEqualTo: 'enrolled')
        .where('isDeleted', isEqualTo: false)
        .get();

    return [
      for (final doc in snap.docs)
        MessageablePerson(
          id: doc.id,
          name: '${doc.data()['firstName'] ?? ''} ${doc.data()['lastName'] ?? ''}'
              .trim(),
          section: section,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The guardians with a portal account linked to one child.
  Future<List<MessageableGuardian>> parentsForStudent(String studentId) async {
    final snap = await _firestore
        .collection(FirestorePaths.users(_actingUser.schoolId))
        .where('role', isEqualTo: 'parent')
        .where('linkedStudentIds', arrayContains: studentId)
        .get();

    return [
      for (final doc in snap.docs)
        MessageableGuardian(
          uid: doc.id,
          name: '${doc.data()['firstName'] ?? ''} ${doc.data()['lastName'] ?? ''}'
              .trim(),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  /// The teachers assigned to one section, one row per person.
  Future<List<TeacherAssignment>> teachersForSection(String section) async {
    final snap = await _firestore
        .collection(FirestorePaths.teacherAssignments(_actingUser.schoolId))
        .where('section', isEqualTo: section)
        .get();

    final byTeacher = <String, TeacherAssignment>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final teacherId = data['teacherId'] as String?;
      if (teacherId == null) continue;
      // One row per teacher, not one per subject they teach the class.
      // A parent choosing who to write to is choosing a person.
      byTeacher.putIfAbsent(
        teacherId,
        () => TeacherAssignment(
          id: doc.id,
          teacherId: teacherId,
          teacherName: (data['teacherName'] as String?) ?? 'Teacher',
          subject: (data['subject'] as String?) ?? '',
          section: (data['section'] as String?) ?? section,
          schoolYear: (data['schoolYear'] as String?) ?? '',
          isAdviser: (data['isAdviser'] as bool?) ?? false,
        ),
      );
    }

    final teachers = byTeacher.values.toList();
    // The adviser first: they are the one person responsible for the
    // class as a whole, and the one a parent most often means.
    teachers.sort((a, b) {
      if (a.isAdviser != b.isAdviser) return a.isAdviser ? -1 : 1;
      return a.teacherName.compareTo(b.teacherName);
    });
    return teachers;
  }
}
