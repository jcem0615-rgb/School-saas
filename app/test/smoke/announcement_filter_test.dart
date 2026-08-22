import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/core/widgets/confirm_delete_dialog.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/presentation/screens/announcements_screen.dart';

/// Every portal -- staff, student and parent -- opens this same screen.
/// That is why the audience filter has to live below it, and why the
/// authoring controls have to be gated on it: for a long time a student
/// opened Announcements and got the staff payroll notice, a "New" button
/// and an edit/delete menu on every card.
void main() {
  Future<void> pumpAs(WidgetTester tester, UserRole role) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const AnnouncementsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// The audience bar scrolls horizontally, and at phone width the later
  /// roles start off-screen -- a bare tap lands on nothing and the test
  /// fails describing the filter rather than the scroll.
  Future<void> tapAudienceChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  group('what each role is shown', () {
    testWidgets('a student does not see the staff-only payroll notice', (tester) async {
      await pumpAs(tester, UserRole.student);

      expect(find.text('Class suspension - Typhoon Signal No. 2'), findsOneWidget,
          reason: 'addressed to everyone');
      expect(find.text('Second Quarter exam schedule posted'), findsOneWidget,
          reason: 'addressed to faculty, student and parent');
      expect(find.text('Payroll cut-off moved to the 25th'), findsNothing,
          reason: 'addressed to staff roles only -- this is the whole bug');
    });

    testWidgets('a parent sees the same two', (tester) async {
      await pumpAs(tester, UserRole.parent);

      expect(find.text('Class suspension - Typhoon Signal No. 2'), findsOneWidget);
      expect(find.text('Second Quarter exam schedule posted'), findsOneWidget);
      expect(find.text('Payroll cut-off moved to the 25th'), findsNothing);
    });

    testWidgets('a faculty member sees the payroll notice but not the whole list',
        (tester) async {
      // The mirror image of the student's list, which is what makes this
      // filtering rather than hiding one awkward document. Faculty rather
      // than admin because admin can author, and authors deliberately get
      // everything (see the management view below).
      await pumpAs(tester, UserRole.faculty);

      expect(find.text('Class suspension - Typhoon Signal No. 2'), findsOneWidget);
      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);
      expect(find.text('Second Quarter exam schedule posted'), findsOneWidget,
          reason: 'faculty are named on that one too');
    });

    testWidgets('a guidance counsellor is not shown the exam schedule', (tester) async {
      await pumpAs(tester, UserRole.guidance);

      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);
      expect(find.text('Second Quarter exam schedule posted'), findsNothing,
          reason: 'addressed to faculty, student and parent -- not guidance');
    });
  });

  group('who may post', () {
    testWidgets('a student gets no authoring controls', (tester) async {
      await pumpAs(tester, UserRole.student);

      expect(find.byType(FloatingActionButton), findsNothing,
          reason: 'a student cannot post an announcement');
      expect(find.byType(RowActionsMenu), findsNothing,
          reason: 'nor edit or delete one');
    });

    testWidgets('a faculty member reads but does not post', (tester) async {
      // Faculty are staff, so they see staff notices -- but firestore.rules
      // only lets director, principal and admin write the collection, and
      // a button that can only ever produce a permission error is worse
      // than no button.
      await pumpAs(tester, UserRole.faculty);

      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a director gets the authoring controls and the audience filter',
        (tester) async {
      await pumpAs(tester, UserRole.director);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byType(RowActionsMenu), findsWidgets);
      expect(find.widgetWithText(FilterChip, 'All'), findsOneWidget,
          reason: 'the audience filter bar is an author tool');
    });
  });

  group('the audience filter', () {
    testWidgets('an author sees everything posted, addressed to them or not', (tester) async {
      // The management view. A director is not named on the payroll
      // notice, but they still have to be able to find and edit it.
      await pumpAs(tester, UserRole.director);

      expect(find.text('Class suspension - Typhoon Signal No. 2'), findsOneWidget);
      expect(find.text('Second Quarter exam schedule posted'), findsOneWidget);
      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);
    });

    testWidgets('narrows the list to what one role would be shown', (tester) async {
      await pumpAs(tester, UserRole.director);

      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);

      await tapAudienceChip(tester, 'Student');

      expect(find.text('Class suspension - Typhoon Signal No. 2'), findsOneWidget);
      expect(find.text('Second Quarter exam schedule posted'), findsOneWidget);
      expect(find.text('Payroll cut-off moved to the 25th'), findsNothing,
          reason: 'a student would not be shown it');
    });

    testWidgets('All puts everything back', (tester) async {
      await pumpAs(tester, UserRole.director);

      await tapAudienceChip(tester, 'Student');
      expect(find.text('Payroll cut-off moved to the 25th'), findsNothing);

      await tapAudienceChip(tester, 'All');
      expect(find.text('Payroll cut-off moved to the 25th'), findsOneWidget);
    });
  });

  testWidgets('an announcement addressed to nobody cannot be posted', (tester) async {
    // "Choose roles" seeds the staff set, so reaching the empty state
    // takes deliberate work -- but an announcement nobody is shown is
    // strictly worse than no announcement, since the author walks away
    // believing they told someone.
    await pumpAs(tester, UserRole.director);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose roles'));
    await tester.pumpAndSettle();

    for (final role in ['Director', 'Principal', 'Admin', 'Registrar / Cashier', 'Faculty', 'Staff', 'Guidance']) {
      final chip = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilterChip, role),
      );
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    expect(find.text('Pick at least one role, or this reaches nobody.'), findsOneWidget);
    final post = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post'));
    expect(post.onPressed, isNull, reason: 'Post must be disabled, not merely warned about');
  });

  testWidgets('posting to a chosen set of roles reaches only those roles', (tester) async {
    // End to end through the editor: the picker is what makes the filter
    // mean anything, since before it every announcement was posted to
    // everyone and the audience field could never be set.
    await pumpAs(tester, UserRole.director);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Faculty meeting');
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'AVR, 4pm.');

    await tester.tap(find.text('Choose roles'));
    await tester.pumpAndSettle();

    // The role chips exist twice while the editor is open -- once in the
    // filter bar behind it, once in the dialog -- so every chip finder
    // here is scoped to the dialog.
    Finder chipInDialog(String label) => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilterChip, label),
        );

    // "Choose roles" seeds the staff set, so reaching faculty-only means
    // clearing the rest rather than ticking eight boxes.
    //
    // ensureVisible is not optional here: the role chips run past the
    // bottom of the dialog's scroll view, and a tap on a clipped one
    // lands on the modal barrier and quietly closes the editor.
    for (final role in ['Staff', 'Admin', 'Registrar / Cashier', 'Guidance']) {
      final chip = chipInDialog(role);
      expect(chip, findsOneWidget, reason: 'no $role chip in the audience picker');
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }

    final post = find.widgetWithText(FilledButton, 'Post');
    await tester.ensureVisible(post);
    await tester.pumpAndSettle();
    await tester.tap(post);
    await tester.pumpAndSettle();

    // It is on the management list, because the author must be able to
    // find what they just posted.
    expect(find.text('Faculty meeting'), findsOneWidget);

    await tapAudienceChip(tester, 'Faculty');
    expect(find.text('Faculty meeting'), findsOneWidget, reason: 'faculty were named');

    await tapAudienceChip(tester, 'Student');
    expect(find.text('Faculty meeting'), findsNothing,
        reason: 'a student would not be shown a faculty-only notice');
  });
}
