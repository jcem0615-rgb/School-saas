import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/messaging/domain/entities/conversation.dart';
import 'package:logicclass/features/messaging/presentation/controllers/messaging_controller.dart';

/// A parent and a teacher talking about one child.
///
/// The refusals are the feature. A teacher may be reached only about a
/// class they teach, a parent only about their own child, and neither
/// can clear the other's unread count -- the demo repositories mirror
/// what firestore.rules and the callable enforce, and each case here is
/// one the server refuses too.
void main() {
  Future<ProviderContainer> signedInAs(UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return container;
  }

  MessagingActionController actions(ProviderContainer container) {
    final sub = container.listen(messagingActionControllerProvider, (_, __) {});
    addTearDown(sub.close);
    return container.read(messagingActionControllerProvider.notifier);
  }

  Conversation thread(DemoStore store, String id) =>
      store.conversations.value.firstWhere((c) => c.id == id);

  const seeded = 'u_faculty__u_parent__stu_001';

  group('who can open a thread', () {
    test('a parent may write to a teacher who teaches their child', () async {
      final container = await signedInAs(UserRole.parent);
      final id = await actions(container).startConversation(
        studentId: 'stu_001',
        otherUid: 'u_faculty',
      );
      // Already seeded, so this returns the existing one rather than a
      // second thread holding half the conversation.
      expect(id, seeded);
      expect(
        container.read(demoStoreProvider).conversations.value
            .where((c) => c.id == seeded)
            .length,
        1,
      );
    });

    test('but not about a child who is not theirs', () async {
      final container = await signedInAs(UserRole.parent);
      final controller = actions(container);

      // stu_004 is somebody else's child.
      final id = await controller.startConversation(
        studentId: 'stu_004',
        otherUid: 'u_faculty',
      );

      expect(id, isNull);
      expect(controller.errorMessage, contains('not linked'));
    });

    test('and not to a teacher who does not teach their child', () async {
      final container = await signedInAs(UserRole.parent);
      final controller = actions(container);

      // u_guidance is staff, but teaches nobody.
      final id = await controller.startConversation(
        studentId: 'stu_001',
        otherUid: 'u_guidance',
      );

      expect(id, isNull);
      expect(controller.errorMessage, contains('does not teach'));
    });

    test('a teacher may write to the parent of a student they teach', () async {
      final container = await signedInAs(UserRole.faculty);
      final id = await actions(container).startConversation(
        studentId: 'stu_001',
        otherUid: 'u_parent',
      );
      expect(id, seeded);
    });

    test('the office cannot open one at all', () async {
      // Deliberate. A conversation between a parent and a teacher is
      // between the two of them; an admin with something to say to a
      // family has announcements.
      final container = await signedInAs(UserRole.admin);
      final controller = actions(container);

      final id = await controller.startConversation(
        studentId: 'stu_001',
        otherUid: 'u_parent',
      );

      expect(id, isNull);
      expect(controller.errorMessage, contains('teacher and a parent'));
    });
  });

  group('sending', () {
    test('lands in the thread and raises only the other side', () async {
      final container = await signedInAs(UserRole.parent);
      final store = container.read(demoStoreProvider);
      final before = store.messages.value[seeded]!.length;
      final teacherUnreadBefore = thread(store, seeded).unreadFor('u_faculty');

      final ok = await actions(container).send(
        conversationId: seeded,
        text: 'He will be in tomorrow po.',
      );

      expect(ok, isTrue);
      expect(store.messages.value[seeded]!.length, before + 1);

      final sent = store.messages.value[seeded]!.last;
      // Stamped from the signed-in account, so nobody puts words in the
      // other person's mouth.
      expect(sent.senderUid, 'u_parent');
      expect(sent.text, 'He will be in tomorrow po.');

      final after = thread(store, seeded);
      expect(after.lastMessage, 'He will be in tomorrow po.');
      expect(after.unreadFor('u_faculty'), teacherUnreadBefore + 1);
      // The sender's own count does not move.
      expect(after.unreadFor('u_parent'), 0);
    });

    test('an empty message is not sent', () async {
      final container = await signedInAs(UserRole.parent);
      final store = container.read(demoStoreProvider);
      final before = store.messages.value[seeded]!.length;

      expect(await actions(container).send(conversationId: seeded, text: '   '),
          isFalse);
      expect(store.messages.value[seeded]!.length, before);
    });

    test('somebody outside the thread cannot send into it', () async {
      final container = await signedInAs(UserRole.registrar);
      final store = container.read(demoStoreProvider);
      final before = store.messages.value[seeded]!.length;

      expect(
        await actions(container).send(conversationId: seeded, text: 'Hello'),
        isFalse,
      );
      expect(store.messages.value[seeded]!.length, before);
    });

    test('and it tells the other person', () async {
      final container = await signedInAs(UserRole.parent);
      final store = container.read(demoStoreProvider);
      final before = (store.notifications.value['u_faculty'] ?? const []).length;

      await actions(container).send(
        conversationId: seeded,
        text: 'Thank you po.',
      );

      final inbox = store.notifications.value['u_faculty'] ?? const [];
      expect(inbox.length, before + 1);
      // Names the child, because a teacher with thirty families needs to
      // know which conversation rang before opening it.
      expect(inbox.first.title, contains('Miguel Torres'));
      expect(inbox.first.link, '/messages');
    });
  });

  group('reading', () {
    test('opening the thread clears only your own count', () async {
      final container = await signedInAs(UserRole.faculty);
      final store = container.read(demoStoreProvider);

      // Seeded with one waiting for the teacher.
      expect(thread(store, seeded).unreadFor('u_faculty'), 1);
      // Give the parent a count too, so the assertion below means
      // something.
      store.update<Conversation>(
        store.conversations,
        (c) => c.id == seeded,
        (c) => Conversation(
          id: c.id,
          participantUids: c.participantUids,
          teacherUid: c.teacherUid,
          teacherName: c.teacherName,
          parentUid: c.parentUid,
          parentName: c.parentName,
          studentId: c.studentId,
          studentName: c.studentName,
          section: c.section,
          lastMessage: c.lastMessage,
          lastMessageAt: c.lastMessageAt,
          lastSenderUid: c.lastSenderUid,
          unread: const {'u_faculty': 1, 'u_parent': 3},
        ),
      );

      await actions(container).markRead(seeded);

      expect(thread(store, seeded).unreadFor('u_faculty'), 0);
      // "I read it" must not become "you read it".
      expect(thread(store, seeded).unreadFor('u_parent'), 3);
    });

    test('a list shows only your own threads', () async {
      final parent = await signedInAs(UserRole.parent);
      final parentThreads = await parent.read(myConversationsProvider.future);
      expect(parentThreads.map((c) => c.id), contains(seeded));

      final registrar = await signedInAs(UserRole.registrar);
      final registrarThreads =
          await registrar.read(myConversationsProvider.future);
      expect(registrarThreads, isEmpty);
    });

    test('the badge counts what is waiting for this account', () async {
      final container = await signedInAs(UserRole.faculty);
      final sub = container.listen(myConversationsProvider, (_, __) {});
      addTearDown(sub.close);
      await container.read(myConversationsProvider.future);

      expect(container.read(unreadMessageCountProvider), 1);

      await actions(container).markRead(seeded);
      await container.read(myConversationsProvider.future);

      expect(container.read(unreadMessageCountProvider), 0);
    });
  });
}
