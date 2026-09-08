import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/admin_portal/presentation/screens/teacher_assignments_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/announcements_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/expenses_screen.dart';
import 'package:logicclass/features/director_portal/presentation/screens/meetings_screen.dart';
import 'package:logicclass/features/emergency/presentation/screens/emergency_contacts_screen.dart';
import 'package:logicclass/features/payments/presentation/screens/fee_structures_screen.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';
import 'package:logicclass/features/schedules/presentation/screens/schedule_screen.dart';
import 'package:logicclass/features/timekeeping/presentation/screens/leave_requests_screen.dart';
import 'package:logicclass/core/router/app_router.dart';
import 'package:logicclass/main.dart';

/// Director and Principal supervise; Admin operates.
///
/// `firestore.rules` is what enforces this, and `oversight-roles.rules.test.ts`
/// is what proves the enforcement. These are the other half: the app must
/// not offer a supervisor a button the server is going to refuse. A
/// filled-in form ending in a permission error is worse than no button,
/// and this codebase says so in several places -- so it is worth checking
/// rather than assuming.
///
/// Both directions are asserted on every screen. A test that only checks
/// the button is absent passes just as well when the screen fails to
/// render at all.
void main() {
  Future<void> pumpAs(WidgetTester tester, UserRole role, Widget screen) async {
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
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Screens both oversight roles can open, and the affordance that is
  /// no longer theirs.
  final operatorOnly = <String, Widget Function()>{
    'the timetable': () => const ScheduleScreen(),
    'teacher assignments': () => const TeacherAssignmentsScreen(),
    'the roll': () => const StudentListScreen(),
    'the expense ledger': () => const ExpensesScreen(),
    'the fee schedules': () => const FeeStructuresScreen(),
    'the emergency numbers': () => const EmergencyContactsScreen(),
  };

  group('a supervisor is not offered a button the server would refuse', () {
    for (final role in [UserRole.director, UserRole.principal]) {
      for (final entry in operatorOnly.entries) {
        testWidgets('a ${role.value} opens ${entry.key} and cannot add to it',
            (tester) async {
          await pumpAs(tester, role, entry.value());
          expect(find.byType(FloatingActionButton), findsNothing,
              reason: '${role.value} must not be offered an add button on ${entry.key}');
          expect(find.byType(FloatingActionButton.extended.runtimeType), findsNothing);
          // The screen still opened, which is the half that must not
          // regress: taking the buttons away is the point, taking the
          // visibility away would defeat it.
          expect(find.byType(Scaffold), findsWidgets);
        });
      }
    }

    for (final entry in operatorOnly.entries) {
      testWidgets('but an admin still can, on ${entry.key}', (tester) async {
        await pumpAs(tester, UserRole.admin, entry.value());
        expect(find.byType(FloatingActionButton), findsWidgets,
            reason: 'the admin operates: ${entry.key} must still be editable');
      });
    }
  });

  group('the leave queue', () {
    // Read by both oversight roles, decided by neither. The queue stays
    // on their dashboard because knowing who is off is supervision; the
    // Approve and Decline buttons are not offered.
    testWidgets('a director sees it and is offered no decision', (tester) async {
      await pumpAs(tester, UserRole.director, const LeaveRequestsScreen());
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.textContaining('waiting on the Admin'), findsWidgets);
    });

    testWidgets('a principal likewise', (tester) async {
      await pumpAs(tester, UserRole.principal, const LeaveRequestsScreen());
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Decline'), findsNothing);
    });

    testWidgets('and the admin decides it', (tester) async {
      await pumpAs(tester, UserRole.admin, const LeaveRequestsScreen());
      expect(find.text('Approve'), findsWidgets);
      expect(find.text('Decline'), findsWidgets);
    });
  });

  group('what a supervisor keeps', () {
    testWidgets('a director can still post an announcement', (tester) async {
      await pumpAs(tester, UserRole.director, const AnnouncementsScreen());
      expect(find.byType(FloatingActionButton), findsWidgets);
    });

    testWidgets('a principal can still post one', (tester) async {
      await pumpAs(tester, UserRole.principal, const AnnouncementsScreen());
      expect(find.byType(FloatingActionButton), findsWidgets);
    });

    testWidgets('a director can still call a meeting', (tester) async {
      await pumpAs(tester, UserRole.director, const MeetingsScreen());
      expect(find.byType(FloatingActionButton), findsWidgets);
    });
  });

  /// The Refund button, which is decided by the router rather than by the
  /// screen -- so it is checked through the router, on the real widget
  /// tree, rather than by handing the screen a flag and asserting the flag
  /// was honoured.
  ///
  /// This is the gate that went stale: `recordRefund` allows the Admin
  /// alone, and the router went on drawing the button for the Director
  /// after the role became oversight-only. A refused refund is not a
  /// harmless dead button -- somebody has already told a family the money
  /// is coming back by the time the server says no.
  group('the refund button', () {
    Future<void> openHistoryAs(WidgetTester tester, UserRole role) async {
      // Tall on purpose. The payment rows sit below the balance breakdown
      // and the instalment plan, and a row that never gets laid out is a
      // row whose button finds nothing -- which would pass this test for
      // the wrong reason. The amount assertion in each case is what makes
      // sure the list actually rendered before the button is judged.
      tester.view.physicalSize = const Size(1200, 7000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const LogicClassApp()),
      );
      await tester.pumpAndSettle();

      final uids = {for (final a in DemoStore.demoAccounts) a.uid};
      container.read(demoStoreProvider).acknowledgedPrivacy.add(uids);
      container.read(demoStoreProvider).acceptedTerms.add(uids);

      demoSignInAs(
        container.read(demoAuthRepositoryProvider),
        container.read(goRouterProvider),
        DemoStore.demoAccounts.firstWhere((a) => a.role == role),
      );
      await tester.pumpAndSettle();

      container.read(goRouterProvider).go('${AppRoutes.paymentHistory}/stu_001');
      await tester.pumpAndSettle();
    }

    final refund = find.widgetWithIcon(IconButton, Icons.undo);

    testWidgets('is the admin\'s, and the history is theirs to act on',
        (tester) async {
      await openHistoryAs(tester, UserRole.admin);
      expect(find.text('\u20B15,000.00'), findsWidgets,
          reason: 'the history did not render, so finding no button proves nothing');
      expect(refund, findsWidgets);
    });

    testWidgets('is not offered to a director, who reads the same history',
        (tester) async {
      await openHistoryAs(tester, UserRole.director);
      expect(find.text('\u20B15,000.00'), findsWidgets);
      expect(refund, findsNothing);
    });

    testWidgets('nor to a principal', (tester) async {
      await openHistoryAs(tester, UserRole.principal);
      expect(find.text('\u20B15,000.00'), findsWidgets);
      expect(refund, findsNothing);
    });

    testWidgets('nor to the registrar, who took the money in the first place',
        (tester) async {
      await openHistoryAs(tester, UserRole.registrar);
      expect(find.text('\u20B15,000.00'), findsWidgets);
      expect(refund, findsNothing);
    });
  });

  group('the role model itself', () {
    test('exactly two roles supervise', () {
      final oversight =
          UserRole.values.where((r) => r.isOversightOnly).map((r) => r.value).toList();
      expect(oversight, ['director', 'principal']);
    });

    test('and neither of them operates', () {
      expect(UserRole.director.canOperate, isFalse);
      expect(UserRole.principal.canOperate, isFalse);
    });

    test('the roles that do the work still do', () {
      for (final role in [
        UserRole.admin,
        UserRole.registrar,
        UserRole.faculty,
        UserRole.staff,
        UserRole.guidance,
      ]) {
        expect(role.canOperate, isTrue, reason: '${role.value} operates');
      }
    });

    test('and a family never did', () {
      expect(UserRole.student.canOperate, isFalse);
      expect(UserRole.parent.canOperate, isFalse);
      expect(UserRole.student.isOversightOnly, isFalse);
      expect(UserRole.parent.isOversightOnly, isFalse);
    });
  });
}
