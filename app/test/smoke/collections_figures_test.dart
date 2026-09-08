import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:logicclass/features/payments/domain/entities/payment.dart';
import 'package:logicclass/features/payments/domain/repositories/payment_repository.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';
import 'package:logicclass/features/reports/domain/entities/report_period.dart';
import 'package:logicclass/features/reports/domain/usecases/collections_report.dart';

/// "How much did the school take today" is computed in three places, and
/// they have to agree.
///
/// A refund is two writes: the original payment keeps its positive amount
/// and flips to `refunded`, and a second row carries the negative with
/// status `completed`. Summing every row therefore nets a refund out on
/// its own -- which is what the Collections report and the School Totals
/// tile already did, and what the Director's dashboard did not. Filtering
/// that aggregate on `status == 'completed'` dropped the original and
/// kept the negative, so a payment taken and refunded on the same day
/// took the day's takings *down* by the full amount instead of leaving
/// them unchanged.
///
/// Nothing tested the dashboard figure, which is why it survived. These
/// pin the arithmetic and, more usefully, pin the three answers to each
/// other.
void main() {
  Future<ProviderContainer> signedInAsDirector() async {
    final container = ProviderContainer(overrides: demoOverrides());
    addTearDown(container.dispose);
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.role == UserRole.director),
        );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final sub = container.listen(dashboardSummaryProvider, (_, __) {});
    addTearDown(sub.close);
    return container;
  }

  Future<String> pay(PaymentRepository repo, double amount) async {
    final result = await repo.recordPayment(
      studentId: 'stu_001',
      amount: amount,
      method: PaymentMethod.cash,
      purpose: PaymentPurpose.tuition,
    );
    return (result as Success<RecordPaymentOutcome>).value.paymentId;
  }

  /// The day's takings as the Director's dashboard reports them.
  ///
  /// Invalidated before each read, and read under a live listener: an
  /// autoDispose provider that nothing is listening to is disposed
  /// mid-flight, and `.future` then throws instead of answering.
  Future<double> dashboardToday(ProviderContainer container) async {
    container.invalidate(dashboardSummaryProvider);
    final summary = await container.read(dashboardSummaryProvider.future);
    return summary.todayPaymentsTotal;
  }

  /// The same day, as the Collections report headlines it.
  String reportCollectedToday(DemoStore store) {
    final today = DateTime.now();
    final table = CollectionsReport.build(
      period: ReportPeriod(today, today),
      students: store.students.value,
      payments: store.payments.value,
      assessments: store.assessments.value,
    );
    return table.headline.firstWhere((s) => s.label == 'Collected').value;
  }

  test('a payment taken and refunded on the same day nets to nothing', () async {
    final container = await signedInAsDirector();
    final store = container.read(demoStoreProvider);
    final repo = container.read(paymentRepositoryProvider);

    final before = await dashboardToday(container);

    final id = await pay(repo, 2500);
    expect(await dashboardToday(container), before + 2500);

    await repo.recordRefund(paymentId: id, reason: 'Paid twice at the counter.');

    // Not `before - 2500`, which is what dropping the refunded original
    // and keeping the negative row produced.
    expect(await dashboardToday(container), before);
    expect(store.payments.value.where((p) => p.isRefund), isNotEmpty,
        reason: 'the refund row exists; it is simply netted, not hidden');
  });

  test('one refund out of three payments leaves the other two standing', () async {
    final container = await signedInAsDirector();
    final repo = container.read(paymentRepositoryProvider);
    final before = await dashboardToday(container);

    await pay(repo, 1000);
    final refunded = await pay(repo, 2500);
    await pay(repo, 400);
    await repo.recordRefund(paymentId: refunded, reason: 'Wrong student.');

    expect(await dashboardToday(container), before + 1400);
  });

  test('the dashboard and the Collections report agree on the same day', () async {
    // The invariant that matters more than either figure: one school,
    // one day, two pieces of code, and they must not disagree. The
    // report's own headline promises "net of refunds", which is the
    // claim the dashboard was breaking.
    final container = await signedInAsDirector();
    final store = container.read(demoStoreProvider);
    final repo = container.read(paymentRepositoryProvider);

    await pay(repo, 3200);
    final refunded = await pay(repo, 1750);
    await repo.recordRefund(paymentId: refunded, reason: 'Duplicate.');

    final fromDashboard = await dashboardToday(container);
    expect(
      NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(fromDashboard),
      reportCollectedToday(store),
    );
  });
}
