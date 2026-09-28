import '../../../../core/errors/result.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
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

  // --- Who this person may write to -------------------------------------
  //
  // Here rather than queried from the screen, which is where they were
  // and which is why the New message sheet could not open in the demo:
  // it was the one place in the app reaching past the repositories into
  // Firestore directly, and the demo has no Firebase at all.
  //
  // None of this decides anything. The callable checks the relationship
  // again before it opens a thread; these lists are what make the
  // screen usable, not what make it safe.

  /// The sections the signed-in teacher is assigned to.
  Future<Result<List<String>>> mySections();

  /// The enrolled students in one section.
  Future<Result<List<MessageablePerson>>> studentsInSection(String section);

  /// The guardians with a portal account linked to one child.
  Future<Result<List<MessageableGuardian>>> parentsForStudent(String studentId);

  /// The teachers assigned to one section, one row per person.
  Future<Result<List<TeacherAssignment>>> teachersForSection(String section);
}
