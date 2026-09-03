import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/core/utils/validators.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_detail_screen.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';

/// The student's own email address and mobile number.
///
/// Neither existed on the record before. The registration form asked for
/// a guardian's name and phone and nothing else, so a student's own
/// contact details lived nowhere -- which had three consequences, and the
/// third is the one nobody would have found by reading the screen:
///
///   * creating a portal account meant typing an address into a dialog
///     that stored it only in Firebase Auth, so the office could not
///     afterwards say what address it had issued;
///   * the school had no way to reach a student directly, only through a
///     guardian who may be at work;
///   * password reset by phone matches against users/{uid}.phone, and
///     nothing ever wrote that field except a person editing their own
///     profile -- which needs a sign-in, which is the thing they cannot
///     do. The feature could not work for anybody who needed it.
void main() {
  group('the record itself', () {
    StudentSummary student({
      String? email,
      String? phone,
      List<GuardianContact> guardians = const [],
    }) =>
        StudentSummary(
          id: 'stu_x',
          studentNumber: '2026-00001',
          firstName: 'Miguel',
          lastName: 'Torres',
          educationLevel: EducationLevel.highSchool,
          gradeLevel: 'Grade 10',
          section: 'Grade 10 - Rizal',
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(2026, 6, 1),
          email: email,
          phone: phone,
          guardianContacts: guardians,
        );

    test('a portal account needs an address on file first', () {
      expect(student().canProvisionAccount, isFalse);
      expect(student(email: 'miguel@student.school.edu.ph').canProvisionAccount, isTrue);
      // Whitespace is not an address. A cell containing a space is what a
      // spreadsheet round trip leaves behind, and it would otherwise turn
      // the Create button on for a record with nothing in it.
      expect(student(email: '   ').canProvisionAccount, isFalse);
    });

    test('reaching a student prefers their own number, then a guardian', () {
      const mother = GuardianContact(
        name: 'Rosario Torres',
        relationship: 'Mother',
        phone: '0917 555 0142',
        email: 'rosario@gmail.com',
      );

      expect(student(phone: '0918 555 0100', guardians: const [mother]).reachablePhone,
          '0918 555 0100');
      // A Grade 4 pupil has no handset. The mother's number is the answer,
      // and it is the answer the office actually wants.
      expect(student(guardians: const [mother]).reachablePhone, '0917 555 0142');
      expect(student().reachablePhone, isNull);

      expect(student(email: 'own@school.ph', guardians: const [mother]).reachableEmail,
          'own@school.ph');
      expect(student(guardians: const [mother]).reachableEmail, 'rosario@gmail.com');
      expect(student().reachableEmail, isNull);
    });

    test('a student nobody can reach reads as nobody, not as an empty string', () {
      // "Which students have no way to be contacted in an emergency?" is a
      // list a school wants before it needs it, and it cannot be built
      // from a column that mixes '' with null.
      final nobody = student(email: '', phone: '');
      expect(nobody.reachablePhone, isNull);
      expect(nobody.reachableEmail, isNull);
    });
  });

  group('what the form and the server agree to accept', () {
    test('both fields may be left empty', () {
      expect(Validators.optionalEmail(''), isNull);
      expect(Validators.optionalEmail(null), isNull);
      expect(Validators.optionalPhilippineMobile(''), isNull);
      expect(Validators.optionalPhilippineMobile(null), isNull);
    });

    test('a school address with a multi-label domain is accepted', () {
      // Most Philippine school addresses are *.edu.ph. A validator that
      // rejects them rejects most of this product's users.
      expect(Validators.optionalEmail('juan@student.sanlorenzo.edu.ph'), isNull);
    });

    test('a typo is refused', () {
      expect(Validators.optionalEmail('juan@gmailcom'), isNotNull);
      expect(Validators.optionalPhilippineMobile('5550100'), isNotNull);
    });

    test('the same number written five ways is one number', () {
      // This mirrors normalizePhone in functions/src/shared/auth/phone.ts,
      // which is what the password reset matches against. If the two ever
      // disagree, a family is locked out by a space.
      const expected = '639171234567';
      for (final shape in [
        '09171234567',
        '+639171234567',
        '9171234567',
        '0917 123 4567',
        '(0917) 123-4567',
      ]) {
        expect(Validators.normalizePhilippineMobile(shape), expected, reason: shape);
      }
    });

    test('a fragment is not a mobile number', () {
      for (final bad in ['12', '5550100', 'not a phone', '']) {
        expect(Validators.normalizePhilippineMobile(bad), isNull, reason: bad);
      }
    });

    test('a landline typed with an extension is not rejected, and that is known', () {
      // '02 8123 4567 ext 5' reduces to enough digits behind a leading
      // zero to look like a mobile, so it passes. That is not right, but
      // it is exactly what normalizePhone on the server does, and these
      // two agreeing matters more than either being clever: a number the
      // client accepts and the server rejects is a save that fails after
      // the round trip, and the reverse is a record the reset cannot use.
      // Pinned here so a future fix is made in both places at once.
      expect(Validators.normalizePhilippineMobile('02 8123 4567 ext 5'), isNotNull);
    });
  });

  group('the registration form', () {
    testWidgets('asks for the student\'s own email and mobile', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: demoOverrides());
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
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Register Student'));
      await tester.pumpAndSettle();

      expect(find.text('Email (optional)'), findsOneWidget);
      expect(find.text('Mobile Number (optional)'), findsOneWidget);
      // The guardian's address too: the record has always had somewhere
      // to put it and the form simply never asked, which for a younger
      // pupil is the only address the school could have had.
      expect(find.text('Guardian Email (optional)'), findsOneWidget);
    });
  });

  group('the student record screen', () {
    Future<void> openDetail(WidgetTester tester, StudentSummary s) async {
      tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: demoOverrides());
      addTearDown(container.dispose);
      container.read(demoAuthRepositoryProvider).signInAs(
            DemoStore.demoAccounts.firstWhere((a) => a.email == 'registrar@demo.ph'),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light(), home: StudentDetailScreen(student: s)),
        ),
      );
      await tester.pumpAndSettle();
    }

    StudentSummary seeded(String id) =>
        DemoStore().students.value.firstWhere((s) => s.id == id);

    testWidgets('shows the address a new account would be created against',
        (tester) async {
      // Andrea has an address on file and no portal account. The button is
      // available, and the screen says what it will use -- which is the
      // fix for a dialog that used to open blank and store the answer
      // where the office could never look it up again.
      await openDetail(tester, seeded('stu_003'));

      final create = find.widgetWithText(FilledButton, 'Create Student Portal Account');
      await tester.scrollUntilVisible(create, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('andrea.villanueva@student.demo.ph'), findsWidgets);
      expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    });

    testWidgets('refuses to create an account for a record with no address',
        (tester) async {
      // Bea is in Grade 4 and has no email, which is ordinary. The button
      // is disabled and the screen says to put the address on the record
      // first -- rather than accepting one typed into a dialog that
      // nobody can read back afterwards.
      await openDetail(tester, seeded('stu_002'));

      final create = find.widgetWithText(FilledButton, 'Create Student Portal Account');
      await tester.scrollUntilVisible(create, 300, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(create).onPressed, isNull);
      expect(find.textContaining('No email on this record yet'), findsOneWidget);
    });

    testWidgets('an edit can clear a wrong number', (tester) async {
      // The direction that matters more than adding one. A number the
      // school believes it can reach a family on, and cannot, is worse
      // than no number: nobody goes looking for a better one.
      final andrea = seeded('stu_003');
      await openDetail(tester, andrea);

      final phoneField = find.widgetWithText(TextField, andrea.phone!);
      expect(phoneField, findsOneWidget);

      await tester.enterText(phoneField, '');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Student record updated.'), findsOneWidget);
    });
  });
}
