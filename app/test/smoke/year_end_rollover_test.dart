import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/promotion.dart';
import 'package:logicclass/features/registrar_portal/domain/repositories/registrar_repository.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/year_end_rollover_screen.dart';

/// The rollover, end to end against the demo store.
///
/// This is the one screen in the app whose mistakes cannot be undone
/// from inside the app, so it is worth driving rather than trusting: a
/// plan that draws up empty, a button that promotes nobody, or one that
/// promotes the same class twice are all failures a unit test on the
/// domain would not catch.
void main() {
  const section = 'Grade 10 - Rizal';

  Future<(ProviderContainer, DemoStore)> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.registrar),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light(), home: const YearEndRolloverScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (container, container.read(demoStoreProvider));
  }

  Future<void> drawUpPlan(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, section);
    await tester.tap(find.widgetWithText(FilledButton, 'Draw up'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is written until somebody asks for it', (tester) async {
    final (_, store) = await pumpScreen(tester);
    final before = store.students.value
        .firstWhere((s) => s.section == section)
        .gradeLevel;

    await drawUpPlan(tester);

    expect(tester.takeException(), isNull);
    // The plan is on screen and the students have not moved.
    expect(find.text('Miguel Torres'), findsOneWidget);
    expect(
      store.students.value.firstWhere((s) => s.section == section).gradeLevel,
      before,
    );
    expect(store.promotions.value, isEmpty);
  });

  testWidgets('the plan says what the marks say, per student', (tester) async {
    await pumpScreen(tester);
    await drawUpPlan(tester);

    // Miguel passed everything; Paolo's maths is below 75. The screen
    // has to show the difference, since a list where every row says the
    // same thing is a list nobody reads.
    expect(find.textContaining('every subject passed'), findsWidgets);
    expect(find.textContaining('below 75'), findsWidgets);
  });

  testWidgets('running it moves the promoted students, once', (tester) async {
    final (_, store) = await pumpScreen(tester);
    await drawUpPlan(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll them over'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final promoted = store.promotions.value;
    expect(promoted, isNotEmpty);

    // Everyone who was promoted has left Grade 10, and everyone who was
    // not is exactly where they were.
    for (final record in promoted) {
      final student = store.students.value
          .firstWhere((s) => s.id == record.decision.studentId);
      if (record.decision.outcome.advances) {
        expect(student.gradeLevel, record.decision.toGradeLevel);
        expect(student.section, record.decision.toSection);
      } else {
        expect(student.gradeLevel, record.decision.fromGradeLevel);
        expect(student.section, record.decision.fromSection);
      }
    }

    // And the button is gone, because there is nobody left to move. A
    // rollover offered twice is how a school ends up with every child
    // two years above where they belong.
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('drawing the plan again shows the work already done', (tester) async {
    final (_, store) = await pumpScreen(tester);
    await drawUpPlan(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll them over'));
    await tester.pumpAndSettle();

    final afterFirst = store.promotions.value.length;
    final gradeLevels = {for (final s in store.students.value) s.id: s.gradeLevel};

    // The registrar comes back to the same section -- because they were
    // interrupted, or because they are not sure whether it went through.
    // What they must not be offered is the chance to do it again.
    await drawUpPlan(tester);

    expect(find.text('Done'), findsWidgets);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(store.promotions.value.length, afterFirst,
        reason: 'redrawing the plan must not write anything');
    for (final student in store.students.value) {
      expect(student.gradeLevel, gradeLevels[student.id],
          reason: 'redrawing the plan must not move anybody');
    }
  });

  testWidgets('and the repository refuses a second run outright', (tester) async {
    // Belt as well as braces: the screen hides the button, but it is the
    // repository that has to be safe. A dropped connection and a retry
    // is the case that matters, and there the button was never the thing
    // standing in the way.
    final (container, store) = await pumpScreen(tester);
    await drawUpPlan(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll them over'));
    await tester.pumpAndSettle();

    final afterFirst = store.promotions.value.length;
    final gradeLevels = {for (final s in store.students.value) s.id: s.gradeLevel};
    final decisions = [for (final p in store.promotions.value) p.decision];

    // runAsync, because this awaits the repository's own latency rather
    // than anything the widget tree will pump for it.
    final outcome = await tester.runAsync(
      () => container.read(registrarRepositoryProvider).runYearEndRollover(
            schoolYear: currentSchoolYear(DateTime.now()),
            decisions: decisions,
          ),
    );

    expect(outcome, isA<Success<RolloverOutcome>>());
    final applied = (outcome as Success<RolloverOutcome>).value;
    expect(applied.applied, 0);
    expect(applied.skipped, decisions.length);

    expect(store.promotions.value.length, afterFirst,
        reason: 'a re-run must not write a second record for anybody');
    for (final student in store.students.value) {
      expect(student.gradeLevel, gradeLevels[student.id],
          reason: 'a re-run must not move anybody a second time');
    }
  });

  testWidgets('an override is what gets applied, and the record keeps both',
      (tester) async {
    final (_, store) = await pumpScreen(tester);
    await drawUpPlan(tester);

    // The screen's central promise: the recommendation is a starting
    // point, and the registrar's decision is what happens.
    await tester.tap(find.byType(DropdownButtonFormField<PromotionOutcome>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retained').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Roll them over'));
    await tester.pumpAndSettle();

    final overridden = store.promotions.value
        .where((p) => p.decision.outcome == PromotionOutcome.retained)
        .toList();
    expect(overridden, hasLength(1));

    final record = overridden.single;
    expect(record.decision.recommended, isNot(PromotionOutcome.retained),
        reason: 'the record has to keep what was recommended, not just what '
            'was decided, or an override looks like what the marks said');
    expect(record.decision.departsFromRecommendation, isTrue);

    // And a retained student is exactly where they were.
    final student =
        store.students.value.firstWhere((s) => s.id == record.decision.studentId);
    expect(student.gradeLevel, record.decision.fromGradeLevel);
    expect(student.section, record.decision.fromSection);
  });
}
