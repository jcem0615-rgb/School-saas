import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/user_roles.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/demo/demo_tour.dart';
import 'package:logicclass/features/admissions/domain/entities/applicant.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/grade.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/quarterly_grade.dart';
import 'package:logicclass/features/inventory/domain/entities/inventory_item.dart';

/// The demo's copy, held to the demo's data.
///
/// Every role in the switcher carries a line saying what is worth opening
/// -- "the bond paper is under its reorder level", "one student is below
/// 75". Those are claims about seeded data, and seeded data changes every
/// time a module lands. A promise the demo no longer keeps is worse than
/// no promise: somebody is shown the app, taps the thing they were told
/// to look at, and finds nothing there.
///
/// So these assert the claims, not the wording.
void main() {
  late DemoStore store;

  setUp(() => store = DemoStore());
  tearDown(() => store.dispose());

  test('every demo account has something to look at', () {
    // A role in the switcher with no line under it is a portal somebody
    // opens with no idea what the point of it is.
    for (final account in DemoStore.demoAccounts) {
      expect(
        demoTourNotes[account.role],
        isNotNull,
        reason: '${account.role.displayName} has no tour note',
      );
      expect(demoTourNotes[account.role]!.trim(), isNotEmpty);
    }
  });

  test('no note is left for a role the demo cannot sign in as', () {
    // The reverse: a line for a role with no account is a line nobody
    // will ever read, and it rots unnoticed.
    final roles = {for (final a in DemoStore.demoAccounts) a.role};
    for (final role in demoTourNotes.keys) {
      expect(roles, contains(role),
          reason: 'a tour note exists for $role, which has no demo account');
    }
  });

  group('the claims the notes make', () {
    test('Staff: the bond paper really is under its reorder level', () {
      final low = lowStock(store.inventory.value);
      expect(low.map((i) => i.name), contains('Bond paper A4'));
    });

    test('Staff: a projector really is out with somebody', () {
      final held = outstandingIssues(store.inventoryMovements.value);
      expect(
        held.keys.where((k) => k.endsWith('|Projector')),
        isNotEmpty,
      );
    });

    test('Registrar: families really are waiting to be rung back', () {
      final waiting = applicantsNeedingFollowUp(
        store.applicants.value,
        asOf: DateTime.now(),
      );
      expect(waiting, isNotEmpty);
    });

    test('Faculty: a Grade 10 - Rizal maths student really is below 75', () {
      final scheme = store.gradingScheme.value;
      final marks = store.grades.value
          .where((g) => g.subject == 'Mathematics' && g.section == 'Grade 10 - Rizal')
          .toList();

      final byStudentTerm = <String, List<Grade>>{};
      for (final mark in marks) {
        (byStudentTerm['${mark.studentId}|${mark.term}'] ??= []).add(mark);
      }

      final failing = byStudentTerm.values
          .map((group) => computeQuarterlyGrade(
                subject: 'Mathematics',
                term: group.first.term,
                grades: group,
                scheme: scheme,
              ))
          .where((g) => g.hasWork && !isPassing(g.finalGrade));

      expect(failing, isNotEmpty,
          reason: 'the Faculty note promises one, and the marks decide it');
    });

    test('Admin: the grading weights are there to be confirmed', () {
      expect(store.gradingScheme.value.weights, isNotEmpty);
    });

    test('Parent: there is a balance to look at', () {
      final owing = store.students.value.where((s) => s.balance > 0);
      expect(owing, isNotEmpty);
    });
  });

  test('the intro does not promise a backend', () {
    // The one thing a visitor must not misread. Everything here is in
    // memory, and saying so is what stops somebody typing real data into
    // it.
    expect(demoTourIntro.toLowerCase(), contains('in-memory'));
  });
}
