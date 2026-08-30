import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/conversation.dart';

class ConversationModel {
  const ConversationModel._();

  static Conversation fromFirestore(String id, Map<String, dynamic> data) {
    return Conversation(
      id: id,
      participantUids: [
        for (final uid in (data['participantUids'] as List<dynamic>? ?? const []))
          if (uid is String) uid,
      ],
      teacherUid: (data['teacherUid'] as String?) ?? '',
      teacherName: (data['teacherName'] as String?) ?? '',
      parentUid: (data['parentUid'] as String?) ?? '',
      parentName: (data['parentName'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      studentName: (data['studentName'] as String?) ?? '',
      section: (data['section'] as String?) ?? '',
      lastMessage: data['lastMessage'] as String?,
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastSenderUid: data['lastSenderUid'] as String?,
      unread: {
        for (final entry in (data['unread'] as Map<dynamic, dynamic>? ?? const {}).entries)
          if (entry.key is String && entry.value is num)
            entry.key as String: (entry.value as num).toInt(),
      },
    );
  }
}

class MessageModel {
  const MessageModel._();

  static Message fromFirestore(String id, Map<String, dynamic> data) {
    return Message(
      id: id,
      senderUid: (data['senderUid'] as String?) ?? '',
      senderName: (data['senderName'] as String?) ?? '',
      senderRole: (data['senderRole'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
      sentAt: (data['sentAt'] as Timestamp?)?.toDate(),
    );
  }
}
