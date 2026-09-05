import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/errors/result.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/registrar_portal/domain/repositories/registrar_repository.dart';
import 'package:logicclass/features/registrar_portal/presentation/controllers/registrar_controller.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_detail_screen.dart';

/// Parent portal accounts, and who can see which child.
///
/// Before this, the parent portal was fully built -- children, attendance,
/// grades, the statement, messaging, emergency alerts -- and completely
/// unreachable. `provisionUser` accepted role 'parent' and the rules read
/// `linkedStudentIds`, but nothing in the app ever called either. On real
/// Firebase a school could not have onboarded a single parent.
///
/// The other half is that `linkedStudentIds` is a permission list. Adding
/// an id hands one family sight of another family's child, and nothing on
/// either screen looks different afterwards, so it goes through a
/// callable that audits rather than a client write.
void main() {
  Future<ProviderContainer> registrarContainer() async {
    final container = ProviderContainer(overrides: demoOverrides());
    container.read(demoAuthRepositoryProvider).signInAs(
          DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
        );
    return container;
  }

  group('who can see a child', () {
    test('the seeded mother sees both of her children, and nobody else does', () async {
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);

      // Miguel and Bea Torres are siblings. One account, linked twice --
      // which is the case that fails if the only path is "create an
      // account per student".
      final miguel = await repo.watchLinkedParents('stu_001').first;
      final bea = await repo.watchLinkedParents('stu_002').first;
      expect(miguel.single.email, 'parent@demo.ph');
      expect(bea.single.email, 'parent@demo.ph');
      expect(miguel.single.uid, bea.single.uid);

      // The count is read from the account's own links, so it cannot
      // disagree with what the rules will actually let her read.
      expect(miguel.single.childCount, 2);
      expect(miguel.single.seesOtherChildren, isTrue);

      // Andrea is not hers.
      expect(await repo.watchLinkedParents('stu_003').first, isEmpty);
    });

    test('linking and unlinking move exactly one child', () async {
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);

      final mother = (await repo.watchLinkedParents('stu_001').first).single;

      await repo.setParentLink(
        parentUid: mother.uid,
        studentId: 'stu_003',
        linked: true,
      );
      expect((await repo.watchLinkedParents('stu_003').first).single.uid, mother.uid);
      // Her existing children are untouched by a link to a third.
      expect(await repo.watchLinkedParents('stu_001').first, hasLength(1));

      await repo.setParentLink(
        parentUid: mother.uid,
        studentId: 'stu_003',
        linked: false,
      );
      expect(await repo.watchLinkedParents('stu_003').first, isEmpty);
      expect(await repo.watchLinkedParents('stu_001').first, hasLength(1));
    });

    test('linking twice does not double-count the child', () async {
      // A registrar clicking twice, or two of them working the same
      // enrolment queue. The count is what the screen shows before
      // somebody removes access, so it has to be right.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);
      final mother = (await repo.watchLinkedParents('stu_001').first).single;

      await repo.setParentLink(parentUid: mother.uid, studentId: 'stu_001', linked: true);
      expect((await repo.watchLinkedParents('stu_001').first).single.childCount, 2);
    });

    test('unlinking the last child leaves an account that sees nothing', () async {
      // A real state, not an error: the family left, or a wrong link was
      // corrected before the right one was made. The account still
      // exists and can still sign in.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);
      final mother = (await repo.watchLinkedParents('stu_001').first).single;

      await repo.setParentLink(parentUid: mother.uid, studentId: 'stu_001', linked: false);
      await repo.setParentLink(parentUid: mother.uid, studentId: 'stu_002', linked: false);

      expect(await repo.watchLinkedParents('stu_001').first, isEmpty);
      final stillThere = await repo.findParentByEmail('parent@demo.ph');
      expect(stillThere, isA<Success<LinkedParent?>>());
      expect((stillThere as Success<LinkedParent?>).value?.childCount, 0);
    });
  });

  group('finding a parent who already has an account', () {
    test('is found by their address, whatever case it was typed in', () async {
      // The second-child case. Without this the office is told the email
      // is taken, invents a second address for one mother, and then
      // neither account shows her both children.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);

      for (final typed in ['parent@demo.ph', 'Parent@Demo.PH', '  parent@demo.ph  ']) {
        final result = await repo.findParentByEmail(typed);
        expect(result, isA<Success<LinkedParent?>>(), reason: typed);
        expect((result as Success<LinkedParent?>).value?.fullName, 'Rosario Torres',
            reason: typed);
      }
    });

    test('an address nobody uses comes back as nobody, not as an error', () async {
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final result =
          await container.read(registrarRepositoryProvider).findParentByEmail('nobody@demo.ph');
      expect(result, isA<Success<LinkedParent?>>());
      expect((result as Success<LinkedParent?>).value, isNull);
    });

    test('creating a second account on a taken address is refused', () async {
      // The refusal is what makes the "link an existing parent" path
      // necessary rather than optional.
      final container = await registrarContainer();
      addTearDown(container.dispose);

      final result = await container.read(registrarRepositoryProvider).provisionParentAccount(
            studentId: 'stu_003',
            firstName: 'Rosario',
            lastName: 'Torres',
            email: 'parent@demo.ph',
          );
      expect(result, isA<Error<ProvisionStudentAccountOutcome>>());
    });
  });

  group('creating a parent account', () {
    test('links the new account to the child in the same step', () async {
      // An account created with no children can sign in and read nothing,
      // which looks broken and produces a phone call to the office.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final repo = container.read(registrarRepositoryProvider);

      final result = await repo.provisionParentAccount(
        studentId: 'stu_003',
        firstName: 'Elena',
        lastName: 'Villanueva',
        email: 'elena.villanueva@gmail.com',
        phone: '0917 555 0143',
      );
      expect(result, isA<Success<ProvisionStudentAccountOutcome>>());

      final linked = (await repo.watchLinkedParents('stu_003').first).single;
      expect(linked.fullName, 'Elena Villanueva');
      expect(linked.childCount, 1);
      // The number goes onto the account, so she can recover it herself.
      expect(linked.phone, '0917 555 0143');
    });
  });

  group('the student record screen', () {
    Future<void> openDetail(WidgetTester tester, ProviderContainer container,
        StudentSummary s) async {
      tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: StudentDetailScreen(student: s)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names the parents who can see this child', (tester) async {
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final miguel =
          container.read(demoStoreProvider).students.value.firstWhere((s) => s.id == 'stu_001');

      await openDetail(tester, container, miguel);
      await tester.scrollUntilVisible(
        find.text('Family Portal Access'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Rosario Torres'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says plainly when nobody can see a child', (tester) async {
      // The state a school most wants to notice, and the one a list of
      // guardian phone numbers hides: somebody is written on the record,
      // so it looks handled, and nobody has a login.
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final andrea =
          container.read(demoStoreProvider).students.value.firstWhere((s) => s.id == 'stu_003');

      await openDetail(tester, container, andrea);
      await tester.scrollUntilVisible(
        find.text('Family Portal Access'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No parent can see this student yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers both creating an account and linking an existing one',
        (tester) async {
      final container = await registrarContainer();
      addTearDown(container.dispose);
      final andrea =
          container.read(demoStoreProvider).students.value.firstWhere((s) => s.id == 'stu_003');

      await openDetail(tester, container, andrea);
      await tester.scrollUntilVisible(
        find.text('Create Parent Portal Account'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Parent Portal Account'), findsOneWidget);
      expect(find.text('Link an existing parent'), findsOneWidget);
    });
  });
}
