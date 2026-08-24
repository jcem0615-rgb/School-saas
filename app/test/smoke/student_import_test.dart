import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/theme/app_theme.dart';
import 'package:logicclass/demo/demo_overrides.dart';
import 'package:logicclass/demo/demo_store.dart';
import 'package:logicclass/features/registrar_portal/presentation/screens/student_list_screen.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/core/data_transfer/csv.dart' show ImportIssue;
import 'package:logicclass/core/data_transfer/import_columns.dart';
import 'package:logicclass/core/data_transfer/workbook.dart';
import 'package:logicclass/features/admin_portal/domain/entities/program.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/registrar_portal/presentation/import/student_import.dart';

/// Bulk import is the one feature here that can quietly create hundreds of
/// wrong records in a single click, so these tests are mostly about what
/// it refuses.
void main() {
  const importHeaders = [
    'Last Name',
    'First Name',
    'Middle Name',
    'Division',
    'Grade Level',
    'Section',
    'Program',
    'Birthday',
    'Guardian Name',
    'Guardian Phone',
  ];

  final programs = [
    const Program(
      id: 'prog_stem',
      name: 'STEM',
      code: 'STEM',
      department: 'Academic',
      educationLevel: EducationLevel.seniorHigh,
    ),
    const Program(
      id: 'prog_cs',
      name: 'BS Computer Science',
      code: 'BSCS',
      department: 'College of Computer Studies',
      educationLevel: EducationLevel.college,
    ),
  ];

  List<String> row({
    String last = 'Dela Cruz',
    String first = 'Maria',
    String middle = 'Santos',
    String division = 'Elementary',
    String grade = 'Grade 4',
    String section = 'Sampaguita',
    String program = '',
    String birthday = '2015-03-07',
    String guardian = 'Ana Dela Cruz',
    String phone = '09171234567',
  }) =>
      [last, first, middle, division, grade, section, program, birthday, guardian, phone];

  Object? parse(List<String> r, {List<StudentSummary> existing = const [], Set<String>? seen}) =>
      StudentImport.parseRow(
        row: r,
        rowNumber: 2,
        programs: programs,
        existing: existing,
        seen: seen ?? <String>{},
      );

  group('a good row', () {
    test('becomes a registrable student', () {
      final parsed = parse(row()) as StudentImportRow;

      expect(parsed.firstName, 'Maria');
      expect(parsed.lastName, 'Dela Cruz');
      expect(parsed.middleName, 'Santos');
      expect(parsed.educationLevel, EducationLevel.elementary);
      expect(parsed.gradeLevel, 'Grade 4');
      expect(parsed.section, 'Sampaguita');
      expect(parsed.programId, isNull);
      expect(parsed.birthDate, DateTime(2015, 3, 7));
      expect(parsed.guardianContacts.single.name, 'Ana Dela Cruz');
      expect(parsed.guardianContacts.single.phone, '09171234567');
    });

    test('a blank middle name is absent, not empty', () {
      final parsed = parse(row(middle: '')) as StudentImportRow;
      expect(parsed.middleName, isNull);
    });

    test('no guardian is no contact, not a nameless one', () {
      final parsed = parse(row(guardian: '', phone: '')) as StudentImportRow;
      expect(parsed.guardianContacts, isEmpty);
    });
  });

  group('divisions', () {
    test('accepts the exported label, the stored value and the shorthand', () {
      for (final text in ['Senior High School', 'senior_high', 'SHS', 'senior high']) {
        final parsed = parse(row(division: text, program: 'STEM')) as StudentImportRow;
        expect(parsed.educationLevel, EducationLevel.seniorHigh, reason: text);
      }
    });

    test('rejects one it does not know rather than guessing', () {
      final issue = parse(row(division: 'Kinder')) as ImportIssue;
      expect(issue.message, contains('Kinder'));
    });

    test('a blank division says it is required', () {
      expect((parse(row(division: '')) as ImportIssue).message, contains('required'));
    });
  });

  group('the programme catalogue', () {
    test('matches a strand by name or by code', () {
      for (final text in ['STEM', 'stem']) {
        final parsed = parse(row(division: 'Senior High School', program: text)) as StudentImportRow;
        expect(parsed.programId, 'prog_stem');
      }
    });

    test('matches a degree by its full name or its code', () {
      for (final text in ['BS Computer Science', 'BSCS']) {
        final parsed = parse(row(division: 'College', grade: '1st Year', program: text))
            as StudentImportRow;
        expect(parsed.programId, 'prog_cs');
      }
    });

    test('will not put a Senior High student on a college programme', () {
      // The registration form filters the dropdown by division; the
      // import has to enforce the same thing rather than trust the file.
      final issue = parse(row(division: 'Senior High School', program: 'BS Computer Science'))
          as ImportIssue;
      expect(issue.message, contains('Senior High School'));
    });

    test('an unknown strand names the screen that would fix it', () {
      final issue =
          parse(row(division: 'Senior High School', program: 'HUMSS')) as ImportIssue;
      expect(issue.message, contains('Strands & Programs'));
    });

    test('is required where the division has one', () {
      expect(
        (parse(row(division: 'Senior High School', program: '')) as ImportIssue).message,
        contains('required'),
      );
    });

    test('is ignored where the division has none', () {
      // An exported Elementary row has a blank Program; a file that put
      // something there anyway should not fail over it.
      final parsed = parse(row(division: 'Elementary', program: 'STEM')) as StudentImportRow;
      expect(parsed.programId, isNull);
    });
  });

  group('birthdays', () {
    test('reads an ISO date, which is what a date cell becomes', () {
      expect((parse(row(birthday: '2015-03-07')) as StudentImportRow).birthDate,
          DateTime(2015, 3, 7));
    });

    test('reads a slashed date month-first', () {
      expect((parse(row(birthday: '3/7/2015')) as StudentImportRow).birthDate,
          DateTime(2015, 3, 7));
    });

    test('reads day-first only when the first number cannot be a month', () {
      expect((parse(row(birthday: '25/12/2012')) as StudentImportRow).birthDate,
          DateTime(2012, 12, 25));
    });

    test('rejects a day that does not exist instead of rolling it forward', () {
      // DateTime(2015, 2, 31) is silently 3 March. A student filed under
      // the wrong birthday is worse than a rejected row.
      expect(parse(row(birthday: '2/31/2015')), isA<ImportIssue>());
    });

    test('rejects a birthday in the future', () {
      final nextYear = DateTime.now().year + 1;
      final issue = parse(row(birthday: '$nextYear-01-01')) as ImportIssue;
      expect(issue.message, contains('future'));
    });

    test('rejects text that is not a date at all', () {
      expect(parse(row(birthday: 'unknown')), isA<ImportIssue>());
    });

    test('is required, the same as it is on the form', () {
      expect((parse(row(birthday: '')) as ImportIssue).message, contains('required'));
    });
  });

  group('duplicates', () {
    test('a student already enrolled is refused', () {
      final existing = [
        StudentSummary(
          id: 'stu_1',
          studentNumber: '2024-00001',
          firstName: 'Maria',
          lastName: 'Dela Cruz',
          educationLevel: EducationLevel.elementary,
          gradeLevel: 'Grade 4',
          section: 'Sampaguita',
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(2024, 6, 1),
          birthDate: DateTime(2015, 3, 7),
        ),
      ];
      final issue = parse(row(), existing: existing) as ImportIssue;
      expect(issue.message, contains('already enrolled'));
    });

    test('a namesake with a different birthday is a different student', () {
      final existing = [
        StudentSummary(
          id: 'stu_1',
          studentNumber: '2024-00001',
          firstName: 'Maria',
          lastName: 'Dela Cruz',
          educationLevel: EducationLevel.elementary,
          gradeLevel: 'Grade 6',
          section: 'Rosal',
          status: StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(2024, 6, 1),
          birthDate: DateTime(2013, 1, 2),
        ),
      ];
      expect(parse(row(), existing: existing), isA<StudentImportRow>());
    });

    test('the same student twice in one file is caught the second time', () {
      final seen = <String>{};
      expect(parse(row(), seen: seen), isA<StudentImportRow>());
      final issue = parse(row(), seen: seen) as ImportIssue;
      expect(issue.message, contains('appears earlier in this file'));
    });
  });

  group('required names', () {
    test('a row with no first name is refused', () {
      expect(parse(row(first: '  ')), isA<ImportIssue>());
    });

    test('a row with no last name is refused', () {
      expect(parse(row(last: '')), isA<ImportIssue>());
    });
  });

  group('a full round trip through a workbook', () {
    test('what this app exports, this app can import', () {
      // The end-to-end claim: export a roster, hand the file to another
      // school, import it there. The export carries three columns the
      // importer has no use for and puts them in a different order --
      // both of which the importer has to absorb.
      const exportHeaders = [
        'Student Number',
        'Last Name',
        'First Name',
        'Middle Name',
        'Division',
        'Grade Level',
        'Section',
        'Program',
        'Birthday',
        'Guardian Name',
        'Guardian Phone',
        'Status',
        'Balance',
      ];
      final bytes = Workbook.encode(exportHeaders, [
        [
          '2023-00118',
          'Muñoz',
          'Karla',
          'Reyes',
          'College',
          '3rd Year',
          'BSCS 3-A',
          'BS Computer Science',
          '2005-11-02',
          'Rosa Muñoz',
          '09181234567',
          'Enrolled',
          '1500.00',
        ],
      ]);

      final table = Workbook.decode(bytes);
      final columns = ImportColumns.resolve(table.first, importHeaders) as List<int>;
      final parsed = StudentImport.parseRow(
        row: ImportColumns.reorder(table[1], columns),
        rowNumber: 2,
        programs: programs,
        existing: const [],
        seen: <String>{},
      ) as StudentImportRow;

      expect(parsed.lastName, 'Muñoz');
      expect(parsed.firstName, 'Karla');
      expect(parsed.educationLevel, EducationLevel.college);
      expect(parsed.gradeLevel, '3rd Year');
      expect(parsed.section, 'BSCS 3-A');
      expect(parsed.programId, 'prog_cs');
      expect(parsed.birthDate, DateTime(2005, 11, 2));
      expect(parsed.guardianContacts.single.phone, '09181234567');
    });
  });

  group('the transfer sheet', () {
    testWidgets('opens with both halves, and the import controls are real',
        (tester) async {
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

      await tester.tap(find.byTooltip('Export / Import'));
      await tester.pumpAndSettle();

      // Export, in the format the request was actually about.
      expect(find.textContaining('to Excel'), findsOneWidget);
      expect(find.text('Export as CSV instead'), findsOneWidget);

      // Import: the section exists at all, which it did not before.
      expect(find.text('Bulk import'), findsOneWidget);
      expect(find.text('Download blank template (.xlsx)'), findsOneWidget);
      expect(find.text('Choose an Excel or CSV file'), findsOneWidget);

      // And the old refusal is gone.
      expect(find.textContaining('Import is not available'), findsNothing);

      expect(tester.takeException(), isNull);
    });
  });
}
