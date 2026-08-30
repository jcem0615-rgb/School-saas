import '../../../../core/errors/result.dart';
import '../entities/conversation.dart';

abstract class MessagingRepository {
  /// The signed-in person's threads, most recent first.
  Stream<List<Conversation>> watchMyConversations();

  Stream<List<Message>> watchMessages(String conversationId);

  /// Opens the thread, or returns the one that already exists.
  ///
  /// Whether these two may talk is decided server-side; a refusal comes
  /// back as a message worth showing ("that teacher does not teach this
  /// student's class") rather than as a generic failure.
  Future<Result<String>> startConversation({
    required String studentId,
    required String otherUid,
  });

  Future<Result<void>> send({
    required String conversationId,
    required String text,
  });

  /// Clears this account's own unread count. Never the other person's.
  Future<Result<void>> markRead(String conversationId);
}
