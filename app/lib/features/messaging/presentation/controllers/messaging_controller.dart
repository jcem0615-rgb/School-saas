import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/firestore_paths.dart';
import '../../../../core/errors/result.dart';
import '../../../admin_portal/domain/entities/teacher_assignment.dart';
import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider, firestoreProvider, firebaseFunctionsProvider;
import '../../data/datasources/messaging_remote_datasource.dart';
import '../../data/repositories_impl/messaging_repository_impl.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/repositories/messaging_repository.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) {
    return const SignedOutMessagingRepository();
  }
  return MessagingRepositoryImpl(
    MessagingRemoteDataSource(
      firestore: ref.watch(firestoreProvider),
      functions: ref.watch(firebaseFunctionsProvider),
      actingUser: ActingMessenger(
        uid: user.uid,
        schoolId: user.schoolId!,
        name: user.fullName,
        role: user.role.value,
      ),
    ),
  );
});

final myConversationsProvider =
    StreamProvider.autoDispose<List<Conversation>>((ref) {
  return ref.watch(messagingRepositoryProvider).watchMyConversations();
});

/// Unread across every thread, for the badge on the Messages tile.
final unreadMessageCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return 0;
  final conversations = ref.watch(myConversationsProvider).valueOrNull ?? const [];
  return conversations.fold(0, (total, c) => total + c.unreadFor(uid));
});

final conversationMessagesProvider =
    StreamProvider.autoDispose.family<List<Message>, String>((ref, conversationId) {
  return ref.watch(messagingRepositoryProvider).watchMessages(conversationId).map(
    (messages) {
      final sorted = [...messages];
      // Newest last, the way a thread reads. A message still waiting for
      // its server timestamp is the newest there is, so nulls sort to
      // the end rather than to the top.
      sorted.sort((a, b) {
        if (a.sentAt == null) return 1;
        if (b.sentAt == null) return -1;
        return a.sentAt!.compareTo(b.sentAt!);
      });
      return sorted;
    },
  );
});

/// The teachers a parent may write to about one child.
///
/// Read from the section's assignments rather than from anything the
/// parent holds. The callable checks the same relationship again before
/// it opens a thread -- this list is what makes the screen usable, not
/// what makes it safe.
final teachersForSectionProvider =
    FutureProvider.autoDispose.family<List<TeacherAssignment>, String>(
        (ref, section) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) return const [];

  final snap = await ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.teacherAssignments(user.schoolId!))
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
  // The adviser first: they are the one person responsible for the class
  // as a whole, and the one a parent most often means.
  teachers.sort((a, b) {
    if (a.isAdviser != b.isAdviser) return a.isAdviser ? -1 : 1;
    return a.teacherName.compareTo(b.teacherName);
  });
  return teachers;
});

/// One student's linked parents, for a teacher opening a thread.
class LinkedParent {
  final String uid;
  final String name;
  const LinkedParent({required this.uid, required this.name});
}

final parentsForStudentProvider =
    FutureProvider.autoDispose.family<List<LinkedParent>, String>(
        (ref, studentId) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) return const [];

  final snap = await ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.users(user.schoolId!))
      .where('role', isEqualTo: 'parent')
      .where('linkedStudentIds', arrayContains: studentId)
      .get();

  return [
    for (final doc in snap.docs)
      LinkedParent(
        uid: doc.id,
        name: '${doc.data()['firstName'] ?? ''} ${doc.data()['lastName'] ?? ''}'
            .trim(),
      ),
  ];
});

/// One student, as the "new message" picker needs them.
class MessageablePerson {
  final String id;
  final String name;
  final String section;
  const MessageablePerson({
    required this.id,
    required this.name,
    this.section = '',
  });
}

/// The sections the signed-in teacher is assigned to.
///
/// From their assignments rather than the timetable, because a teacher
/// can be an adviser to a class they do not have a timetabled block
/// with, and that is exactly the class whose parents they most need to
/// reach.
final mySectionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) return const [];

  final snap = await ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.teacherAssignments(user.schoolId!))
      .where('teacherId', isEqualTo: user.uid)
      .get();

  final sections = <String>{
    for (final doc in snap.docs)
      if (doc.data()['section'] case final String section) section,
  }.toList()
    ..sort();
  return sections;
});

/// The enrolled students in one section.
final studentsInSectionProvider =
    FutureProvider.autoDispose.family<List<MessageablePerson>, String>(
        (ref, section) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || user.schoolId == null) return const [];

  final snap = await ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.students(user.schoolId!))
      .where('section', isEqualTo: section)
      .where('status', isEqualTo: 'enrolled')
      .where('isDeleted', isEqualTo: false)
      .get();

  final students = [
    for (final doc in snap.docs)
      MessageablePerson(
        id: doc.id,
        name: '${doc.data()['firstName'] ?? ''} ${doc.data()['lastName'] ?? ''}'
            .trim(),
        section: section,
      ),
  ]..sort((a, b) => a.name.compareTo(b.name));
  return students;
});

class MessagingActionController extends StateNotifier<AsyncValue<void>> {
  /// A getter, so this notifier survives the repository rebuilding on
  /// every auth emission rather than being torn down mid-send.
  final MessagingRepository Function() _repository;

  MessagingActionController(this._repository) : super(const AsyncValue.data(null));

  /// Returns the conversation id, or null with [errorMessage] set.
  Future<String?> startConversation({
    required String studentId,
    required String otherUid,
  }) async {
    _set(const AsyncValue.loading());
    final result = await _repository().startConversation(
      studentId: studentId,
      otherUid: otherUid,
    );
    switch (result) {
      case Success(:final value):
        _set(const AsyncValue.data(null));
        return value;
      case Error(:final failure):
        _set(AsyncValue.error(failure.message, StackTrace.current));
        return null;
    }
  }

  Future<bool> send({required String conversationId, required String text}) async {
    // Refused here as well as in the rules: an empty bubble tells the
    // other person nothing and still rings their phone.
    if (text.trim().isEmpty) return false;
    return _run(() => _repository().send(
          conversationId: conversationId,
          text: text.trim(),
        ));
  }

  Future<void> markRead(String conversationId) async {
    await _repository().markRead(conversationId);
  }

  Future<bool> _run(Future<Result<void>> Function() action) async {
    _set(const AsyncValue.loading());
    final result = await action();
    switch (result) {
      case Success():
        _set(const AsyncValue.data(null));
        return true;
      case Error(:final failure):
        _set(AsyncValue.error(failure.message, StackTrace.current));
        return false;
    }
  }

  void _set(AsyncValue<void> next) {
    if (mounted) state = next;
  }

  String? get errorMessage => state.hasError ? state.error.toString() : null;
}

final messagingActionControllerProvider =
    StateNotifierProvider<MessagingActionController, AsyncValue<void>>((ref) {
  return MessagingActionController(() => ref.read(messagingRepositoryProvider));
});
