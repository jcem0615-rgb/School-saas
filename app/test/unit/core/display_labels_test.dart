import 'package:flutter_test/flutter_test.dart';

import 'package:school_saas/core/constants/education_level.dart';
import 'package:school_saas/core/constants/user_roles.dart';
import 'package:school_saas/features/registrar_portal/domain/entities/student_summary.dart';

/// Two things this app said twice on every screen that showed them.
///
/// On a desktop that is untidy. On a phone it is half of a two-line
/// subtitle spent repeating a word, which pushes the part somebody
/// actually needed off the right-hand edge.
void main() {
  StudentSummary student({required String gradeLevel, required String section}) => StudentSummary(
        id: 's',
        studentNumber: '2024-00001',
        firstName: 'Miguel',
        lastName: 'Torres',
        educationLevel: EducationLevel.highSchool,
        gradeLevel: gradeLevel,
        section: section,
        status: StudentStatus.enrolled,
        balance: 0,
        enrollmentDate: DateTime(2026, 6, 1),
      );

  group('classLabel', () {
    test('does not repeat the grade when the section already names it', () {
      // The case that was wrong everywhere: PH sections are named after
      // their grade, so "$gradeLevel - $section" read
      // "Grade 10 - Grade 10 - Rizal".
      expect(
        student(gradeLevel: 'Grade 10', section: 'Grade 10 - Rizal').classLabel,
        'Grade 10 - Rizal',
      );
    });

    test('is not fooled by capitalisation', () {
      expect(
        student(gradeLevel: 'Grade 10', section: 'GRADE 10 - Rizal').classLabel,
        'GRADE 10 - Rizal',
      );
    });

    test('keeps both when the section says something new', () {
      // A college section carries no year, so the year still has to
      // appear or the label loses information.
      expect(
        student(gradeLevel: '3rd Year', section: 'BSCS 3-A').classLabel,
        '3rd Year - BSCS 3-A',
      );
    });

    test('survives a record missing either half', () {
      expect(student(gradeLevel: '', section: 'Grade 4 - Sampaguita').classLabel,
          'Grade 4 - Sampaguita');
      expect(student(gradeLevel: 'Grade 4', section: '').classLabel, 'Grade 4');
      expect(student(gradeLevel: '', section: '').classLabel, '');
    });

    test('ignores stray whitespace rather than rendering it', () {
      expect(
        student(gradeLevel: ' Grade 11 ', section: ' STEM 11-A ').classLabel,
        'Grade 11 - STEM 11-A',
      );
    });
  });

  group('role.labelWith', () {
    test('drops a position that is just the role again', () {
      // The employee list read "Staff · Staff", "Guidance · Guidance",
      // "Admin · Admin" -- a whole subtitle carrying no information.
      expect(UserRole.staff.labelWith('Staff'), 'Staff');
      expect(UserRole.guidance.labelWith('Guidance'), 'Guidance');
      expect(UserRole.admin.labelWith('admin'), 'Admin');
    });

    test('keeps a position that earns its place', () {
      expect(
        UserRole.faculty.labelWith('College Instructor'),
        'Faculty · College Instructor',
      );
      expect(UserRole.staff.labelWith('Canteen Supervisor'), 'Staff · Canteen Supervisor');
    });

    test('falls back to the role when there is no position at all', () {
      expect(UserRole.director.labelWith(null), 'Director');
      expect(UserRole.director.labelWith(''), 'Director');
      expect(UserRole.director.labelWith('   '), 'Director');
    });
  });
}
