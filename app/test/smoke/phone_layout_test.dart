import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/employee_list_screen.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';

/// What the app looks like on the device most of these users actually
/// have.
///
/// Rendered at 390x844 -- an ordinary phone -- because that is where a
/// repeated word costs something. A subtitle has two lines there, and
/// spending one of them saying "Grade 10" twice pushes the part somebody
/// needed off the right edge.
void main() {
  Future<void> pumpAs(WidgetTester tester, UserRole role, Widget screen) async {
    // A real phone, not the 800x600 the test harness defaults to.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
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
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  /// Any RenderFlex overflow in a pumped frame is recorded as an
  /// exception; a clean frame means nothing ran off the edge.
  void expectNoOverflow(WidgetTester tester, String where) {
    expect(tester.takeException(), isNull, reason: '$where overflowed at phone width');
  }

  group('the student roll', () {
    testWidgets('names a class once, not twice', (tester) async {
      await pumpAs(tester, UserRole.registrar, const StudentListScreen());

      // Was "... · Grade 4 - Grade 4 - Sampaguita". The roll is sorted
      // by surname and a phone shows only the first few rows, so this
      // asserts on Alvarez rather than on someone below the fold.
      expect(find.textContaining('Grade 4 - Grade 4'), findsNothing,
          reason: 'the section already carries the grade');
      expect(find.textContaining('Grade 10 - Grade 10'), findsNothing);
      expect(
        find.textContaining('2024-00051 · Elementary · Grade 4 - Sampaguita'),
        findsOneWidget,
      );
      expectNoOverflow(tester, 'Student Records');
    });

    testWidgets('still shows the year when the section does not carry it', (tester) async {
      // A Senior High section is named for its strand, not its year, so
      // dropping the year would lose real information rather than remove
      // a repetition. (College rows show the degree programme instead of
      // a class, which is why the case is checked on Senior High.)
      await pumpAs(tester, UserRole.registrar, const StudentListScreen());

      // Scoped to the roll: the division filter chips are a second
      // scrollable, and an unscoped scroll cannot tell them apart.
      await tester.dragUntilVisible(
        find.text('Trisha Mercado'),
        find.byType(ListView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Grade 11 - STEM 11-A'), findsOneWidget);
    });
  });

  group('the employee list', () {
    testWidgets('does not print the role twice', (tester) async {
      await pumpAs(tester, UserRole.admin, const EmployeeListScreen());

      // Was "Staff · Staff", "Guidance · Guidance", "Admin · Admin" --
      // an entire subtitle carrying nothing.
      for (final doubled in [
        'Staff · Staff',
        'Guidance · Guidance',
        'Admin · Admin',
        'Director · Director',
        'Registrar / Cashier · Registrar / Cashier',
      ]) {
        expect(find.text(doubled), findsNothing, reason: '"$doubled" says one thing twice');
      }
      expectNoOverflow(tester, 'Employee Management');
    });

    testWidgets('keeps a job title that says something the role does not', (tester) async {
      await pumpAs(tester, UserRole.admin, const EmployeeListScreen());

      expect(find.text('Staff · Canteen Supervisor'), findsOneWidget);
      expect(find.text('Faculty · College Instructor'), findsOneWidget);
    });
  });
}
