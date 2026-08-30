import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/app_exceptions.dart';
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
  Stream<List<Conversation>> watchMyConversations() {
    return _conversations
        .where('participantUids', arrayContains: _actingUser.uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ConversationModel.fromFirestore(d.id, d.data()))
            .toList());
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
}
