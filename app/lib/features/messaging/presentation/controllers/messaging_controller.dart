import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Everything the New message sheet needs, through the repository.
///
/// These were four Firestore queries written into this file, which made
/// the sheet the one screen in the app reaching past the repositories.
/// It meant the sheet could not open in the demo -- there is no
/// Firebase there at all -- and that none of it was ever tested.
///
/// None of them decides anything. The callable checks the relationship
/// again before it opens a thread; these make the screen usable, not
/// safe.

/// The teachers a parent may write to about one child.
final teachersForSectionProvider =
    FutureProvider.autoDispose.family<List<TeacherAssignment>, String>(
        (ref, section) async {
  if (section.isEmpty) return const [];
  return _orEmpty(
      await ref.watch(messagingRepositoryProvider).teachersForSection(section));
});

/// One student's linked guardians, for a teacher opening a thread.
final parentsForStudentProvider =
    FutureProvider.autoDispose.family<List<MessageableGuardian>, String>(
        (ref, studentId) async {
  if (studentId.isEmpty) return const [];
  return _orEmpty(
      await ref.watch(messagingRepositoryProvider).parentsForStudent(studentId));
});

/// The sections the signed-in teacher is assigned to.
final mySectionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  return _orEmpty(await ref.watch(messagingRepositoryProvider).mySections());
});

/// The enrolled students in one section.
final studentsInSectionProvider =
    FutureProvider.autoDispose.family<List<MessageablePerson>, String>(
        (ref, section) async {
  if (section.isEmpty) return const [];
  return _orEmpty(
      await ref.watch(messagingRepositoryProvider).studentsInSection(section));
});

/// A refusal reads as "nobody to write to", which is what the sheet
/// shows anyway, rather than as a red error over a picker.
List<T> _orEmpty<T>(Result<List<T>> result) => switch (result) {
      Success(:final value) => value,
      Error() => const [],
    };

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
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.length > maxMessageLength) {
      // The rules refuse this too, but a permission error is not
      // something anybody can act on. Said in the length the person
      // actually typed.
      _set(AsyncValue.error(
        'That message is ${trimmed.length} characters. '
        'The limit is $maxMessageLength -- send it in two.',
        StackTrace.current,
      ));
      return false;
    }
    return _run(() => _repository().send(
          conversationId: conversationId,
          text: trimmed,
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
