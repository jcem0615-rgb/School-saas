import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_repositories.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';

/// Paging the student list is a cost decision before it is a UI one: the
/// screen used to read every student in the school every time someone
/// opened it. These tests hold the two halves of that in place -- that a
/// page really is a page, and that the callers who need everyone still get
/// everyone.
void main() {
  group('DemoRegistrarRepository paging', () {
    late DemoStore store;
    late DemoRegistrarRepository repository;

    setUp(() {
      store = DemoStore();
      addTearDown(store.dispose);
      repository = DemoRegistrarRepository(store);
    });

    test('a limit truncates the page, surname order', () async {
      final page = await repository.watchStudents(limit: 3).first;
      final all = await repository.watchStudents().first;

      expect(page, hasLength(3));
      expect(page.map((s) => s.id), all.take(3).map((s) => s.id),
          reason: 'the first page has to be the first three of the same order, '
              'or Load more shows you students you have already scrolled past');
      expect(
        page.map((s) => s.lastName).toList(),
        orderedEquals([...page.map((s) => s.lastName)]..sort()),
      );
    });

    test('no limit is the whole roster', () async {
      final all = await repository.watchStudents().first;
      expect(all, hasLength(store.students.value.length));
    });

    test('a limit larger than the roster is not an error', () async {
      final page = await repository.watchStudents(limit: 500).first;
      expect(page, hasLength(store.students.value.length));
    });

    test('the division filter runs before the limit, not after', () async {
      // The bug this guards: filter the page instead of the query and
      // asking for two College students hands back however many of the
      // first two students happened to be in College -- often none.
      final page =
          await repository.watchStudents(limit: 2, educationLevel: EducationLevel.college).first;

      expect(page, hasLength(2));
      expect(page.every((s) => s.educationLevel == EducationLevel.college), isTrue);
    });

    test('export reads everyone, not the page on screen', () async {
      final everyone = await repository.fetchAllStudents();
      expect(everyone, hasLength(store.students.value.length));
      expect(everyone.length, greaterThan(4),
          reason: 'the demo page size is 4; an export that returned a page '
              'would look plausible and be wrong');
    });
  });

  group('the paged provider', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
          );
    });

    Future<List<StudentSummary>> paged() =>
        container.read(pagedStudentsStreamProvider.future);

    test('demo mode pages small enough that Load more is reachable', () async {
      final pageSize = container.read(studentPageSizeProvider);
      final total = container.read(demoStoreProvider).students.value.length;
      expect(total, greaterThan(pageSize),
          reason: 'a demo whose roster fits in one page can never show paging');
    });

    test('the first page is one page', () async {
      final pageSize = container.read(studentPageSizeProvider);
      expect(await paged(), hasLength(pageSize));
    });

    test('load more widens the same query', () async {
      final pageSize = container.read(studentPageSizeProvider);
      final first = await paged();

      container.read(studentPageLimitProvider.notifier).update((n) => n + pageSize);
      final second = await paged();

      expect(second.length, greaterThan(first.length));
      expect(second.take(first.length).map((s) => s.id), first.map((s) => s.id),
          reason: 'widening must extend the list, not reshuffle it');
    });

    test('load more stops at the end of the roster', () async {
      container.read(studentPageLimitProvider.notifier).state = 1000;
      final everyone = await paged();
      expect(everyone, hasLength(container.read(demoStoreProvider).students.value.length));
    });

    test('the division filter reaches the query', () async {
      container.read(studentDivisionFilterProvider.notifier).state = EducationLevel.college;
      final page = await paged();

      expect(page, isNotEmpty);
      expect(page.every((s) => s.educationLevel == EducationLevel.college), isTrue);
    });
  });

  group('the student list screen', () {
    late ProviderContainer container;

    Future<void> pumpList(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: const StudentListScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    /// The footer sits under the last student, which on a phone means
    /// under the fold. Scrolling to it is what a registrar does too.
    ///
    /// Counting rendered ListTiles would be the obvious way to check a
    /// page, and it is wrong: a ListView builds a screenful plus a cache
    /// margin, so eight loaded students can be five built widgets. What
    /// the page holds is what the provider emitted; what the screen shows
    /// is what these finders are for.
    Future<void> scrollToFooter(WidgetTester tester) async {
      final list = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      );
      for (var i = 0; i < 15; i++) {
        if (find.textContaining('Showing ').evaluate().isNotEmpty) return;
        await tester.drag(list.first, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
    }

    List<StudentSummary> loaded() =>
        container.read(pagedStudentsStreamProvider).value ?? const [];

    testWidgets('shows one page and a way to see the rest', (tester) async {
      await pumpList(tester);
      final pageSize = container.read(studentPageSizeProvider);

      expect(loaded(), hasLength(pageSize));

      await scrollToFooter(tester);
      expect(find.text('Showing $pageSize students'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('Load more actually adds students', (tester) async {
      await pumpList(tester);
      final pageSize = container.read(studentPageSizeProvider);
      final firstPage = loaded().map((s) => s.id).toList();

      await scrollToFooter(tester);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      final second = loaded();
      expect(second, hasLength(pageSize * 2));
      expect(second.take(pageSize).map((s) => s.id), firstPage,
          reason: 'widening must extend the list, not reshuffle it');

      // And the newly arrived students are reachable on screen, not just
      // in the provider.
      await scrollToFooter(tester);
      expect(find.text(second.last.fullName), findsOneWidget);
    });

    testWidgets('the last page says so instead of offering more', (tester) async {
      await pumpList(tester);
      final total = container.read(demoStoreProvider).students.value.length;
      final pageSize = container.read(studentPageSizeProvider);

      for (var i = 0; i < (total / pageSize).ceil() + 1; i++) {
        await scrollToFooter(tester);
        if (find.text('Load more').evaluate().isEmpty) break;
        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();
      }

      expect(loaded(), hasLength(total));
      expect(find.text('Load more'), findsNothing);
      expect(find.text('Showing all $total students'), findsOneWidget);
    });

    testWidgets('search reaches past the page you are on', (tester) async {
      await pumpList(tester);

      // Someone who is not on the first page -- the exact student a naive
      // "filter what is already loaded" implementation would fail to find.
      final pageSize = container.read(studentPageSizeProvider);
      final roster = [...container.read(demoStoreProvider).students.value]
        ..sort((a, b) => a.lastName.compareTo(b.lastName));
      final offPage = roster[pageSize + 1];
      expect(loaded().map((s) => s.id), isNot(contains(offPage.id)),
          reason: 'the point of the test is that this student is not loaded yet');

      await tester.enterText(find.byType(TextField).first, offPage.lastName);
      await tester.pumpAndSettle();

      expect(find.text(offPage.fullName), findsOneWidget);
      expect(find.textContaining('matching student'), findsOneWidget);
    });

    testWidgets('clearing the search goes back to one page', (tester) async {
      await pumpList(tester);
      final pageSize = container.read(studentPageSizeProvider);

      await tester.enterText(find.byType(TextField).first, 'a');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();

      expect(loaded(), hasLength(pageSize));
      await scrollToFooter(tester);
      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('a division chip re-queries and resets the page', (tester) async {
      await pumpList(tester);
      final pageSize = container.read(studentPageSizeProvider);

      await scrollToFooter(tester);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(container.read(studentPageLimitProvider), pageSize * 2);

      // The chip row scrolls sideways and College is the last chip, so on
      // a 390-point screen it starts off the right edge.
      final chip = find.text(EducationLevel.college.displayLabel);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();

      expect(container.read(studentPageLimitProvider), pageSize,
          reason: 'a new filter is a new list; carrying the old page count '
              'over asks Firestore for records nobody scrolled to');
      expect(container.read(studentDivisionFilterProvider), EducationLevel.college);
      expect(loaded(), isNotEmpty);
      expect(loaded().every((s) => s.educationLevel == EducationLevel.college), isTrue);
    });
  });
}
