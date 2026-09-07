import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payroll/domain/entities/contribution_scheme.dart';
import 'package:logicclass/features/payroll/domain/entities/payroll_run.dart';
import 'package:logicclass/features/payroll/presentation/controllers/payroll_controller.dart';
import 'package:logicclass/features/payroll/presentation/screens/payroll_run_screen.dart';

/// A payroll run, end to end.
///
/// What a payslip contains is tested to the centavo elsewhere, in two
/// languages. What is tested here is the shape the run screen depends
/// on, and the two refusals a school would otherwise find out about on
/// payday: that a period cannot be issued twice, and that nothing issues
/// against contribution tables nobody has confirmed.
///
/// Demo-backed, so this exercises the copy of the arithmetic the demo
/// runs on. The real one is `runPayroll`, covered against a live
/// Firestore in `functions/test/shared/payroll-emulator/`.
void main() {
  Future<ProviderContainer> adminContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'admin@demo.ph'),
        );
    return container;
  }

  final month = DateTime(DateTime.now().year, DateTime.now().month);
  final query = PayrollRunQuery(month: month);

  /// The run, with something holding the provider open while it loads.
  ///
  /// Both payroll providers are autoDispose, and a bare `read` from a
  /// container nothing is listening to disposes them mid-flight -- which
  /// is a fact about this harness, not about the screen, where the
  /// widget is the listener.
  Future<PayrollRun> preview(ProviderContainer container) {
    return container
        .listen(payrollPreviewProvider(query).future, (_, __) {})
        .read();
  }

  /// Every state the action controller passes through.
  ///
  /// Collected rather than read at the end, because that is how the
  /// screen consumes it -- `ref.listen`, surfacing each error as it
  /// arrives.
  List<AsyncValue<void>> watchActions(ProviderContainer container) {
    final seen = <AsyncValue<void>>[];
    container.listen(payrollActionControllerProvider, (_, next) => seen.add(next));
    return seen;
  }

  /// Issues, reading the notifier afresh.
  ///
  /// Not a held instance: issuing writes payslips, the payslip stream
  /// emits, and the controller is rebuilt underneath. The screen does
  /// the same thing for the same reason -- it reads `.notifier` inside
  /// the button handler rather than holding one from build time, and a
  /// held one would be unmounted by the time the second press landed.
  Future<int?> issue(ProviderContainer container) =>
      container.read(payrollActionControllerProvider.notifier).issuePayroll(query);

  group('drafting a run', () {
    test('prices everybody who has a rate on file', () async {
      final container = await adminContainer();
      addTearDown(container.dispose);

      final run = await preview(container);
      expect(run.committed, isFalse);
      expect(run.issued, 0);
      expect(run.canIssue, isTrue);
      expect(run.blockers, isEmpty);
      expect(
        run.payslips.map((p) => p.employeeUid).toList()..sort(),
        ['u_faculty', 'u_guidance', 'u_staff'],
      );
      // Nothing is written by a preview.
      expect(container.read(demoStoreProvider).payslips.value, isEmpty);
    });

    test('the totals on the screen are the run\'s own, not a second sum',
        () async {
      final container = await adminContainer();
      addTearDown(container.dispose);

      final run = await preview(container);
      expect(
        run.totalNetPay,
        run.payslips.fold<double>(0, (sum, p) => sum + p.netPay),
      );
      expect(run.totalEmployerContributions, greaterThan(0));
    });
  });

  group('issuing', () {
    test('writes the run, and refuses to write it again', () async {
      // The failure this exists to stop is quiet: nothing errors, the
      // screen looks right, and everybody is paid twice for one month.
      final container = await adminContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);

      final seen = watchActions(container);
      expect(await issue(container), 3);
      expect(store.payslips.value, hasLength(3));

      expect(await issue(container), isNull);
      expect(store.payslips.value, hasLength(3));

      final refusal = seen.whereType<AsyncError<void>>().single;
      expect(refusal.error.toString(), contains('already been issued'));
    });

    test('refuses while the contribution tables are unconfirmed', () async {
      // The refusal that makes the confirmation mean something. These
      // are somebody's deductions.
      final container = await adminContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);
      store.contributionScheme.add(
        ContributionScheme(tables: store.contributionScheme.value.tables),
      );

      final run = await preview(container);
      // Still priced, so a school can see the figures while it works
      // through the tables.
      expect(run.payslips, hasLength(3));
      expect(run.canIssue, isFalse);
      expect(run.blockers.single, contains('not been confirmed'));

      final seen = watchActions(container);
      expect(await issue(container), isNull);
      expect(
        seen.whereType<AsyncError<void>>().single.error.toString(),
        contains('not been confirmed'),
      );
      expect(store.payslips.value, isEmpty);
    });
  });

  group('the run screen', () {
    testWidgets('shows the month, the total and every employee', (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await adminContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PayrollRunScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Ricardo Aquino'), findsOneWidget);
      expect(find.text('Cecilia Lim'), findsOneWidget);
      expect(find.text('Issue 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says what is blocking a run rather than only greying it out',
        (tester) async {
      tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = await adminContainer();
      addTearDown(container.dispose);
      final store = container.read(demoStoreProvider);
      store.contributionScheme.add(
        ContributionScheme(tables: store.contributionScheme.value.tables),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PayrollRunScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nothing can be issued yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
