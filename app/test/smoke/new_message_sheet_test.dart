import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/messaging/presentation/controllers/messaging_controller.dart';
import 'package:logicclass/features/messaging/presentation/widgets/new_conversation_sheet.dart';

/// The New message sheet, opened for real.
///
/// It opened onto "Your classes could not be loaded: TypeError" because
/// it queried Firestore from its own providers instead of going through
/// the repository, and demo mode never initialises Firebase. Nothing
/// tested it, so nothing caught it. This does.
void main() {
  Future<ProviderContainer> open(WidgetTester tester, UserRole role) async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showNewConversationSheet(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return container;
  }

  group('a teacher writing to a family', () {
    testWidgets('opens without an error where the classes should be',
        (tester) async {
      await open(tester, UserRole.faculty);

      expect(tester.takeException(), isNull);
      expect(find.text('New message'), findsOneWidget);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(find.textContaining('TypeError'), findsNothing);
    });

    testWidgets('offers the three choices as dropdowns, all at once',
        (tester) async {
      // Not three screens with no way back. Picking the wrong class
      // used to mean closing the sheet and starting again.
      await open(tester, UserRole.faculty);

      expect(find.text('Class'), findsOneWidget);
      expect(find.text('Student'), findsOneWidget);
      expect(find.text('Guardian to message'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    });

    testWidgets('holds the later ones shut until the earlier ones are made',
        (tester) async {
      await open(tester, UserRole.faculty);

      expect(find.text('Choose a class first'), findsOneWidget);
      expect(find.text('Choose a student first'), findsOneWidget);
    });

    testWidgets('will not send until there is somebody to send to',
        (tester) async {
      await open(tester, UserRole.faculty);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start message'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('names a class, a student and a guardian in turn',
        (tester) async {
      final container = await open(tester, UserRole.faculty);
      final store = container.read(demoStoreProvider);
      final section = store.students.value.first.section;

      // Class.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(section).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Choose a class first'), findsNothing);

      // Student.
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      final pupil = store.students.value
          .firstWhere((s) => s.section == section)
          .fullName;
      await tester.tap(find.text(pupil).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // And the guardian dropdown is now live rather than telling them
      // to choose a student.
      expect(find.text('Choose a student first'), findsNothing);
    });

    testWidgets('clears the student when the class changes', (tester) async {
      // A student from the class you just moved away from is not a
      // student you meant to write about.
      final container = await open(tester, UserRole.faculty);
      final store = container.read(demoStoreProvider);
      // The teacher's own sections, which is what the dropdown offers --
      // not every section in the school.
      final sections = container.read(mySectionsProvider).valueOrNull ?? const [];
      if (sections.length < 2) return;

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(sections.first).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      final pupil =
          store.students.value.firstWhere((s) => s.section == sections.first);
      await tester.tap(find.text(pupil.fullName).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(sections[1]).last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'a stale selection in a changed list throws on build');
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start message'),
      );
      expect(button.onPressed, isNull, reason: 'the student went with the class');
    });
  });

  group('a parent writing to a teacher', () {
    testWidgets('opens, and asks who to message', (tester) async {
      await open(tester, UserRole.parent);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('could not be loaded'), findsNothing);
      expect(find.text('About which child'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
    });

    testWidgets('opens the teachers once a child is named', (tester) async {
      await open(tester, UserRole.parent);

      // Held shut until there is a child to look their teachers up by.
      expect(find.text('Choose a child first'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownMenuItem<String>).last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Choose a child first'), findsNothing);
    });
  });

  group('everybody else', () {
    testWidgets('is told who messaging is for, not shown empty dropdowns',
        (tester) async {
      await open(tester, UserRole.registrar);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('between parents and their'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Start message'), findsNothing);
    });
  });
}
