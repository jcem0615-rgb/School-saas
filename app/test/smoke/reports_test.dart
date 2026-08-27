import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/reports/domain/entities/report_kind.dart';
import 'package:logicclass/features/reports/domain/entities/report_period.dart';
import 'package:logicclass/features/reports/presentation/controllers/reports_controller.dart';

/// The builders are unit-tested against lists. What these check is the
/// wiring above them: that a report asks for what it needs, that the
/// period actually filters, and that the figures line up with the same
/// store the rest of the demo reads.
Future<ProviderContainer> _signedInAs(UserRole role) async {
  final container = ProviderContainer(overrides: demoOverrides());
  container.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('the enrollment report counts the same students the roster shows', () async {
    final container = await _signedInAs(UserRole.director);
    addTearDown(container.dispose);

    container.read(reportRequestProvider.notifier).state = ReportRequest(
      kind: ReportKind.enrollment,
      period: ReportPeriod.schoolYearOf(DateTime.now()),
    );
    final table = await container.read(reportTableProvider.future);

    final store = container.read(demoStoreProvider);
    final enrolled = store.students.value.where((s) => s.status.value == 'enrolled').length;

    expect(table.title, 'Enrollment by Division');
    expect(table.headline.first.value, '$enrolled');
    expect(table.rows.where((r) => r.isTotal), hasLength(1));
  });

  test('a report only reads what it needs', () async {
    final container = await _signedInAs(UserRole.director);
    addTearDown(container.dispose);

    // Enrollment is a head count. Pulling a term of attendance scans to
    // answer it would be invisible on screen and expensive in a real
    // deployment, so the kind declares its sources and the repository
    // honours them.
    final data = await container.read(reportsRepositoryProvider).fetch(
          kind: ReportKind.enrollment,
          period: ReportPeriod.schoolYearOf(DateTime.now()),
        );
    final value = data.valueOrNull!;
    expect(value.students, isNotEmpty);
    expect(value.attendance, isEmpty);
    expect(value.grades, isEmpty);
    expect(value.payments, isEmpty);
  });

  test('the period actually narrows the collections report', () async {
    final container = await _signedInAs(UserRole.director);
    addTearDown(container.dispose);
    final notifier = container.read(reportRequestProvider.notifier);

    notifier.state = ReportRequest(
      kind: ReportKind.collections,
      period: ReportPeriod.schoolYearOf(DateTime.now()),
    );
    final wide = await container.read(reportTableProvider.future);

    // A window in the far past cannot contain any seeded payment, so
    // the collected figure has to fall to nothing. A report whose totals
    // do not move when the dates do is one that is ignoring them.
    notifier.state = ReportRequest(
      kind: ReportKind.collections,
      period: ReportPeriod(DateTime(2021, 1, 1), DateTime(2021, 1, 31)),
    );
    container.invalidate(reportTableProvider);
    final narrow = await container.read(reportTableProvider.future);

    expect(wide.headline.first.label, 'Collected');
    expect(wide.headline.first.value, isNot('₱0.00'));
    expect(narrow.headline.first.value, '₱0.00');
    expect(
      narrow.headline[1].value,
      wide.headline[1].value,
      reason: 'outstanding is a running balance and does not move with the dates',
    );
  });

  test('every report builds against the seeded school without throwing', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final notifier = container.read(reportRequestProvider.notifier);

    for (final kind in ReportKind.values) {
      notifier.state = ReportRequest(
        kind: kind,
        period: ReportPeriod.schoolYearOf(DateTime.now()),
      );
      container.invalidate(reportTableProvider);
      final table = await container.read(reportTableProvider.future);
      expect(table.title, kind.title, reason: 'wrong builder for $kind');
      expect(
        table.columns.length,
        table.rows.isEmpty ? table.columns.length : table.rows.first.cells.length,
        reason: '$kind has a row that does not match its own columns',
      );
    }
  });
}
