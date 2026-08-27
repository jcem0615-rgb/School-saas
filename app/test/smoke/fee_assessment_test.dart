import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/presentation/controllers/payment_controller.dart';

/// An assessment moves two things at once: the itemised record and the
/// balance. `firestore.rules` keeps `balance` server-only, so in the real
/// app that pair is a callable transaction and in demo mode it is the
/// demo repository -- either way the two must never come apart, which is
/// what these check.
Future<ProviderContainer> _signedInAs(UserRole role) async {
  final container = ProviderContainer(overrides: demoOverrides());
  container.read(demoAuthRepositoryProvider).signInAs(
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
  // The demo repositories watch authStateProvider so a role switch
  // re-subscribes every stream; reading a controller before that lands
  // hands back one that is disposed mid-write.
  await Future<void>.delayed(const Duration(milliseconds: 100));
  return container;
}

void main() {
  test('the seeded assessments account for the balances exactly', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final store = container.read(demoStoreProvider);

    // A breakdown that does not add up reads as a bug in the school's
    // books, so the demo has to reconcile: charged - paid == balance.
    for (final studentId in ['stu_001', 'stu_009']) {
      final student = store.students.value.firstWhere((s) => s.id == studentId);
      final charged = store.assessments.value
          .where((a) => a.studentId == studentId)
          .fold<double>(0, (sum, a) => sum + a.effectiveTotal);
      final paid = store.payments.value
          .where((p) => p.studentId == studentId && p.refundOf == null)
          .fold<double>(0, (sum, p) => sum + p.amount);

      expect(
        charged - paid,
        closeTo(student.balance, 0.001),
        reason: '$studentId: ${student.balance} should be $charged charged less $paid paid',
      );
    }
  });

  test('assessing fees raises the balance and files an itemised record', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final before = store.students.value.firstWhere((s) => s.id == 'stu_005').balance;

    final outcome =
        await container.read(paymentActionControllerProvider.notifier).assessStudentFees(
              studentId: 'stu_005',
              schoolYear: '2026-2027',
              items: const [
                FeeItem(label: 'Tuition', amount: 15000, category: FeeCategory.tuition),
                FeeItem(label: 'Laboratory Fee', amount: 2500),
              ],
              remarks: 'Second semester',
            );

    expect(outcome, isNotNull);
    expect(outcome!.total, 17500);
    expect(outcome.newBalance, closeTo(before + 17500, 0.001));
    expect(
      store.students.value.firstWhere((s) => s.id == 'stu_005').balance,
      closeTo(before + 17500, 0.001),
      reason: 'the student record itself has to move, not just the return value',
    );

    final filed = store.assessments.value.firstWhere((a) => a.id == outcome.assessmentId);
    expect(filed.items.map((i) => i.label), ['Tuition', 'Laboratory Fee']);
    expect(filed.total, 17500);
    expect(filed.isVoided, isFalse);
  });

  test('voiding an assessment puts the balance back and keeps the record', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final before = store.students.value.firstWhere((s) => s.id == 'stu_001').balance;
    final existing = store.assessments.value.firstWhere((a) => a.studentId == 'stu_001');

    final ok = await container.read(paymentActionControllerProvider.notifier).voidAssessment(
          assessmentId: existing.id,
          reason: 'Assessed under the wrong schedule',
        );

    expect(ok, isTrue);
    expect(
      store.students.value.firstWhere((s) => s.id == 'stu_001').balance,
      closeTo(before - existing.total, 0.001),
    );

    // Voided, not deleted: the charge and its reversal both stay on the
    // record, which is the only way anyone can reconstruct the balance.
    final after = store.assessments.value.firstWhere((a) => a.id == existing.id);
    expect(after.isVoided, isTrue);
    expect(after.voidReason, 'Assessed under the wrong schedule');
    expect(after.total, existing.total, reason: 'the original charge is still readable');
    expect(after.effectiveTotal, 0);
  });

  test('a reversal cannot be applied twice', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final existing = store.assessments.value.firstWhere((a) => a.studentId == 'stu_001');
    final notifier = container.read(paymentActionControllerProvider.notifier);

    expect(await notifier.voidAssessment(assessmentId: existing.id, reason: 'Wrong schedule'), isTrue);
    final afterFirst = store.students.value.firstWhere((s) => s.id == 'stu_001').balance;

    expect(
      await notifier.voidAssessment(assessmentId: existing.id, reason: 'Again'),
      isFalse,
      reason: 'two cashiers voiding at once would otherwise reverse the charge twice',
    );
    expect(store.students.value.firstWhere((s) => s.id == 'stu_001').balance, afterFirst);
  });

  test('the same schedule cannot be charged twice for the same year', () async {
    final container = await _signedInAs(UserRole.registrar);
    addTearDown(container.dispose);
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final structure = store.feeStructures.value.first;
    final notifier = container.read(paymentActionControllerProvider.notifier);

    final first = await notifier.assessStudentFees(
      studentId: 'stu_005',
      schoolYear: structure.schoolYear,
      items: structure.items,
      sourceStructureId: structure.id,
      sourceStructureName: structure.name,
    );
    expect(first, isNotNull);
    final balance = store.students.value.firstWhere((s) => s.id == 'stu_005').balance;

    // Two taps on the same schedule is the mistake this feature makes
    // easy, and the family silently owes double when it lands.
    final second = await notifier.assessStudentFees(
      studentId: 'stu_005',
      schoolYear: structure.schoolYear,
      items: structure.items,
      sourceStructureId: structure.id,
      sourceStructureName: structure.name,
    );
    expect(second, isNull);
    expect(store.students.value.firstWhere((s) => s.id == 'stu_005').balance, balance);
  });

  test('a schedule saved by an admin is offered to the registrar', () async {
    final container = await _signedInAs(UserRole.admin);
    addTearDown(container.dispose);
    final sub = container.listen(paymentActionControllerProvider, (_, __) {});
    addTearDown(sub.close);

    final store = container.read(demoStoreProvider);
    final ok = await container.read(paymentActionControllerProvider.notifier).saveFeeStructure(
          name: 'Grade 4 - Full Year',
          educationLevel: EducationLevel.elementary,
          gradeLevel: 'Grade 4',
          schoolYear: '2026-2027',
          items: const [
            FeeItem(label: 'Tuition', amount: 9000, category: FeeCategory.tuition),
            FeeItem(label: 'Books', amount: 1500, category: FeeCategory.miscellaneous),
          ],
        );

    expect(ok, isTrue);
    final saved = store.feeStructures.value.firstWhere((s) => s.name == 'Grade 4 - Full Year');
    expect(saved.total, 10500);
    expect(
      saved.appliesTo(level: EducationLevel.elementary, studentGradeLevel: 'Grade 4'),
      isTrue,
    );
    expect(
      saved.appliesTo(level: EducationLevel.elementary, studentGradeLevel: 'Grade 5'),
      isFalse,
    );
  });
}
