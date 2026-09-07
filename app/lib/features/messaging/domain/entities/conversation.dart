/// A thread between one parent and one of their child's teachers.
///
/// One per child rather than one per pair: a parent with two children
/// taught by the same teacher gets two threads, and "which child is this
/// about" stays answerable without anybody having to say so in the first
/// message.
///
/// Created only by the `startConversation` callable, which is where the
/// question of whether these two people may talk at all is settled --
/// deciding it needs a query over the teacher's assignments, and
/// firestore.rules can only fetch a document by path.
class Conversation {
  final String id;

  /// Both people, in one array, so a single `array-contains` query
  /// serves either side's list.
  final List<String> participantUids;

  final String teacherUid;
  final String teacherName;
  final String parentUid;
  final String parentName;

  /// The child the thread is about.
  final String studentId;
  final String studentName;
  final String section;

  /// A one-line preview, written server-side when a message lands.
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastSenderUid;

  /// Per participant, so each side's badge is its own. Nobody can clear
  /// the other person's.
  final Map<String, int> unread;

  /// When the thread was opened.
  ///
  /// Kept because a thread nobody has written in yet has no
  /// [lastMessageAt], and sorting on a null puts a conversation somebody
  /// has just started at the very bottom of their list -- under threads
  /// from last term. [sortedAt] is what the list actually orders by.
  final DateTime? createdAt;

  const Conversation({
    required this.id,
    required this.participantUids,
    required this.teacherUid,
    required this.teacherName,
    required this.parentUid,
    required this.parentName,
    required this.studentId,
    required this.studentName,
    required this.section,
    required this.unread,
    this.lastMessage,
    this.lastMessageAt,
    this.lastSenderUid,
    this.createdAt,
  });

  /// What a conversation list is ordered by: when it was last spoken in,
  /// or when it was opened if it has not been.
  DateTime? get sortedAt => lastMessageAt ?? createdAt;

  /// The other person's name, from the point of view of [uid].
  String otherName(String uid) => uid == teacherUid ? parentName : teacherName;

  /// And their uid.
  String otherUid(String uid) => uid == teacherUid ? parentUid : teacherUid;

  int unreadFor(String uid) => unread[uid] ?? 0;

  /// Nothing has been said yet. Shown as such rather than as an empty
  /// line, because a blank row reads as a thread that failed to load.
  bool get isEmpty => lastMessageAt == null;
}

/// A message long enough to be a problem rather than a message.
///
/// Kept in step with `MAX_MESSAGE_LENGTH` in
/// `functions/src/shared/messaging/conversation.ts` and with the cap in
/// `firestore.rules`, which is the one that actually refuses. Checked
/// here as well so a long paste is answered by the box it was pasted
/// into rather than by a permission error from the server.
const int maxMessageLength = 4000;

/// One message. Never edited, never unsent.
class Message {
  final String id;
  final String senderUid;
  final String senderName;
  final String senderRole;
  final String text;

  /// Null for the single frame between a message being written and the
  /// server stamping it, which is exactly when the sender is looking at
  /// it. Callers sort nulls last -- the one still in flight is the
  /// newest there is.
  final DateTime? sentAt;

  const Message({
    required this.id,
    required this.senderUid,
    required this.senderName,
    required this.senderRole,
    required this.text,
    this.sentAt,
  });
}
