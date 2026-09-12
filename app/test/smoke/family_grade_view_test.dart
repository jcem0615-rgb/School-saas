import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/parent_portal/presentation/screens/child_detail_screen.dart';
import 'package:logicclass/features/student_portal/presentation/screens/subject_detail_screen.dart';

/// What a family is shown about a grade.
///
/// The two things this pins are the two ways a provisional grade gets
/// misread. A student reading 89 at the top of their own subject page has
/// no reason to think it is anything but their grade -- so the page has
/// to say when it is not final. And a parent who can see every mark but
/// never the grade those marks add up to is the wrong way round: the
/// child could see it, the person who has to act on it could not.
void main() {
  /// No awaited delay here on purpose: inside testWidgets a bare
  /// `Future.delayed` runs on the real clock while the widget clock
  /// stands still, so the screen never gets past its spinner and
  /// pumpAndSettle waits for ten minutes. Signing in and pumping is what
  /// the other widget tests in this suite do, and it works because
  /// pumping is what advances both.
  ProviderContainer signedInAs(UserRole role) {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == role),
        );
    return container;
  }

  testWidgets('a subject still missing a component reads INC, not a number',
      (tester) async {
    tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = signedInAs(UserRole.student);
    final student = container.read(demoStoreProvider).students.value.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: SubjectDetailScreen(
            subject: 'Mathematics',
            section: student.section,
            studentId: student.id,
            teacherName: 'Maria Santos',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('INC'), findsOneWidget,
        reason: 'the quarter has no quarterly assessment in it yet');
    expect(find.textContaining('not finished yet'), findsOneWidget);
    // And the working figure is still there, labelled as provisional
    // rather than hidden -- a student is entitled to know where they are.
    expect(find.textContaining('so far, out of the'), findsOneWidget);
    expect(find.textContaining('Still to come'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a parent can reach the grade, not only the marks behind it',
      (tester) async {
    tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = signedInAs(UserRole.parent);
    final child = container.read(demoStoreProvider).students.value.first;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: ChildDetailScreen(child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Subjects and grades'), findsOneWidget);
    expect(find.text('Every mark'), findsOneWidget);

    await tester.tap(find.text('Subjects and grades'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'a parent reads the grading scheme too -- the rules allow '
            'any member of the school, and a screen that threw here would '
            'be an offer the server refuses');
  });
}
