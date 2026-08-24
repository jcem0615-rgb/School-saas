import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/director_portal/domain/entities/announcement.dart';
import 'package:logicclass/features/director_portal/presentation/controllers/director_controller.dart';
import 'package:logicclass/features/director_portal/presentation/screens/announcements_screen.dart';

/// A teacher's notice to their class is only useful if it reaches that
/// class and stops there. These tests cover both halves — the reaching
/// and the stopping — because getting either wrong is silent: nobody
/// reports an announcement they never saw.
void main() {
  group('AnnouncementAudience', () {
    const toRizal = AnnouncementAudience(
      all: false,
      roles: [],
      sections: ['Grade 10 - Rizal'],
    );

    test('reaches a viewer in that section whatever their role', () {
      for (final role in [UserRole.student, UserRole.parent, UserRole.faculty]) {
        expect(
          toRizal.includes(role, viewerSections: const ['Grade 10 - Rizal']),
          isTrue,
          reason: '${role.value} in the section must be reached',
        );
      }
    });

    test('stops at a viewer in a different section', () {
      expect(
        toRizal.includes(UserRole.student, viewerSections: const ['Grade 4 - Sampaguita']),
        isFalse,
      );
    });

    test('stops at someone who belongs to no section at all', () {
      // An admin or a cashier. A class reminder is not for them, and the
      // absence of a section must not read as "matches everything".
      expect(toRizal.includes(UserRole.admin), isFalse);
    });

    test('a parent of two children is reached through either', () {
      expect(
        toRizal.includes(UserRole.parent,
            viewerSections: const ['Grade 4 - Sampaguita', 'Grade 10 - Rizal']),
        isTrue,
      );
    });

    test('a role-targeted notice ignores sections entirely', () {
      const staffOnly = AnnouncementAudience(all: false, roles: ['admin'], sections: []);
      expect(staffOnly.includes(UserRole.admin), isTrue);
      expect(
        staffOnly.includes(UserRole.student, viewerSections: const ['Grade 10 - Rizal']),
        isFalse,
      );
    });

    test('everyone still means everyone', () {
      expect(AnnouncementAudience.everyone.includes(UserRole.student), isTrue);
    });

    test('an audience with nothing chosen reaches nobody, and says so', () {
      const empty = AnnouncementAudience(all: false, roles: [], sections: []);
      expect(empty.reachesNobody, isTrue);
      expect(empty.includes(UserRole.student, viewerSections: const ['Grade 10 - Rizal']),
          isFalse);
      expect(empty.label, 'No one');
    });

    test('the label names the section, so a list row says who it is for', () {
      expect(toRizal.label, 'Grade 10 - Rizal');
      expect(AnnouncementAudience.everyone.label, 'Everyone');
    });
  });

  group('who belongs to which section', () {
    ProviderContainer signedInAs(String email) {
      final c = ProviderContainer(overrides: demoOverrides());
      addTearDown(c.dispose);
      c.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == email),
          );
      return c;
    }

    /// Reads through a held subscription, and waits for the upstream
    /// streams to emit.
    ///
    /// Both halves matter. viewerSectionsProvider is autoDispose, so a
    /// bare `read` tears it down again before the roster stream it
    /// depends on has produced anything, and the answer is always empty.
    Future<T> settled<T>(ProviderContainer c, ProviderListenable<T> p, bool Function(T) until) async {
      final sub = c.listen(p, (_, __) {});
      addTearDown(sub.close);
      for (var i = 0; i < 25 && !until(sub.read()); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return sub.read();
    }

    test('a student belongs to their own section', () async {
      final sections = await settled(
          signedInAs('student@demo.ph'), viewerSectionsProvider, (s) => s.isNotEmpty);
      expect(sections, ['Grade 10 - Rizal']);
    });

    test("a parent belongs to their children's sections", () async {
      final sections = await settled(
          signedInAs('parent@demo.ph'), viewerSectionsProvider, (s) => s.isNotEmpty);
      expect(sections, isNotEmpty);
    });

    test('a teacher belongs to every section they are assigned to, once each', () async {
      final sections = await settled(
          signedInAs('faculty@demo.ph'), viewerSectionsProvider, (s) => s.isNotEmpty);

      expect(sections, contains('Grade 10 - Rizal'));
      expect(sections.toSet().length, sections.length,
          reason: 'Maria Santos takes three subjects in that one section');
    });

    test('an admin belongs to none', () async {
      // Given every chance to produce something before being believed.
      final sections = await settled(
          signedInAs('admin@demo.ph'), viewerSectionsProvider, (s) => s.isNotEmpty);
      expect(sections, isEmpty);
    });

    test('a teacher may post to their sections, advisory listed first', () async {
      final options = await settled(
          signedInAs('faculty@demo.ph'), myTeachingSectionsProvider, (o) => o.isNotEmpty);

      expect(options, isNotEmpty);
      expect(options.first.isAdviser, isTrue,
          reason: 'the class they advise is the one they mean most often');
      expect(options.map((a) => a.section).toSet().length, options.length,
          reason: 'one row per section, not per subject');
    });
  });

  group('the seeded class notice', () {
    Future<void> pumpAs(WidgetTester tester, String email) async {
      tester.view.physicalSize = const Size(1080, 4800);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == email),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: const AnnouncementsScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
    }

    const notice = 'Bring your permit slip on Friday';

    testWidgets('the Grade 10 student sees it', (tester) async {
      await pumpAs(tester, 'student@demo.ph');
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('their parent sees it', (tester) async {
      await pumpAs(tester, 'parent@demo.ph');
      expect(find.text(notice), findsOneWidget);
    });

    testWidgets('the registrar does not', (tester) async {
      // Belongs to no class. This is the half that is silent when wrong:
      // a section notice leaking to the whole school looks like nothing
      // until somebody complains about the noise.
      await pumpAs(tester, 'registrar@demo.ph');
      expect(find.text(notice), findsNothing);
    });

    testWidgets('the teacher who wrote it sees it with an audience line',
        (tester) async {
      await pumpAs(tester, 'faculty@demo.ph');
      expect(find.text(notice), findsOneWidget);
      expect(find.textContaining('Grade 10 - Rizal'), findsWidgets);
    });
  });
}
