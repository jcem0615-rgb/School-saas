import '../../../../core/constants/education_level.dart';
import '../../../../core/data_transfer/csv.dart' show ImportIssue;
import '../../../../core/data_transfer/sheet_values.dart';
import '../../../../core/utils/validators.dart';
import '../../../admin_portal/domain/entities/program.dart';
import '../../domain/entities/student_summary.dart';

/// Turns spreadsheet rows into students the Registrar could have typed.
///
/// Lives apart from the screen because this is where an import is right
/// or wrong. Every check below mirrors one the New Student form makes: an
/// import that could create records the form would have refused would
/// just be a way of getting bad data in through the side door, and the
/// only way to know it still mirrors the form is to be able to test it
/// without building a widget.
class StudentImport {
  StudentImport._();

  /// Validates one spreadsheet row into something registrable.
  ///
  /// Every check here mirrors one the New Student form makes. An import
  /// that could create records the form would have refused would just be
  /// a way of getting bad data in through the side door.
  static Object? parseRow({
    required List<String> row,
    required int rowNumber,
    required List<Program> programs,
    required List<StudentSummary> existing,
    required Set<String> seen,
  }) {
    final lastName = row[0].trim();
    final firstName = row[1].trim();
    final middleName = row[2].trim();
    final divisionText = row[3].trim();
    final gradeLevel = row[4].trim();
    final section = row[5].trim();
    final programText = row[6].trim();
    final birthdayText = row[7].trim();
    final email = row[8].trim();
    final phone = row[9].trim();
    final guardianName = row[10].trim();
    final guardianPhone = row[11].trim();
    final guardianEmail = row.length > 12 ? row[12].trim() : '';

    if (firstName.isEmpty || lastName.isEmpty) {
      return ImportIssue(rowNumber, 'First and last name are required.');
    }

    final division = parseDivision(divisionText);
    if (division == null) {
      return ImportIssue(
        rowNumber,
        divisionText.isEmpty
            ? 'Division is required.'
            : 'Unknown division "$divisionText".',
      );
    }

    if (gradeLevel.isEmpty) {
      return ImportIssue(
        rowNumber,
        division == EducationLevel.college
            ? 'Year level is required.'
            : 'Grade level is required.',
      );
    }
    if (section.isEmpty) return ImportIssue(rowNumber, 'Section is required.');

    // Only the two divisions that have a catalogue get one. A Program
    // value on an Elementary row is ignored rather than rejected --
    // that is what an exported Elementary row looks like anyway.
    String? programId;
    if (division.usesProgramCatalogue) {
      if (programText.isEmpty) {
        return ImportIssue(rowNumber, '${division.programLabel} is required for ${division.displayLabel}.');
      }
      final match = programs
          .where((p) =>
              p.educationLevel == division &&
              (p.name.toLowerCase() == programText.toLowerCase() ||
                  p.code.toLowerCase() == programText.toLowerCase()))
          .firstOrNull;
      if (match == null) {
        return ImportIssue(
          rowNumber,
          'No ${division.programLabel.toLowerCase()} called "$programText" in '
          '${division.displayLabel}. Add it under Strands & Programs first.',
        );
      }
      programId = match.id;
    }

    // Optional, unlike on the form. The form asks one person for one
    // birthday and can insist; a bulk import is usually fed by whatever
    // the school's previous system held, and rejecting three hundred
    // rows because that system never recorded birthdays would leave the
    // roster out of the app entirely. A record with no birth date is
    // still a valid enrolment (see StudentSummary.birthDate) -- the ID
    // card just prints without that line until someone fills it in.
    //
    // A birthday that *is* present still has to be a real one. Silently
    // accepting an unreadable date would be worse than either.
    DateTime? birthDate;
    if (birthdayText.isNotEmpty) {
      birthDate = parseBirthday(birthdayText);
      if (birthDate == null) {
        return ImportIssue(
          rowNumber,
          'Could not read the birthday "$birthdayText". Use a date cell, '
          'write it as 2012-03-07, or leave the cell empty.',
        );
      }
      if (birthDate.isAfter(DateTime.now())) {
        return ImportIssue(rowNumber, 'Birthday $birthdayText is in the future.');
      }
    }

    // Name plus birthday, because a school genuinely does have two Juan
    // Reyes, and a shared birthday as well is the point at which a human
    // should look. Checked against the roster and against the rest of the
    // file.
    //
    // Two rows with the same name and no birthday on either count as the
    // same student. That is the strict reading, and the right one: an
    // import cannot tell them apart, so it should stop and let a person
    // decide rather than quietly enrol a duplicate.
    // The same two checks the New Student form makes, for the same
    // reason: an address with a typo becomes a sign-in nobody can reach,
    // and a number the matcher cannot read recovers nothing. Refusing the
    // row names the student and the column; accepting it hands the school
    // a record that looks complete and is not.
    final emailError = Validators.optionalEmail(email);
    if (emailError != null) {
      return ImportIssue(rowNumber, 'Email for $firstName $lastName: $emailError');
    }
    final phoneError = Validators.optionalPhilippineMobile(phone);
    if (phoneError != null) {
      return ImportIssue(rowNumber, 'Mobile number for $firstName $lastName: $phoneError');
    }
    final guardianEmailError = Validators.optionalEmail(guardianEmail);
    if (guardianEmailError != null) {
      return ImportIssue(
        rowNumber,
        'Guardian email for $firstName $lastName: $guardianEmailError',
      );
    }

    final stamp = birthDate == null ? '' : isoDate(birthDate);
    final key = '${firstName.toLowerCase()}|${lastName.toLowerCase()}|$stamp';
    if (existing.any((s) =>
        s.firstName.toLowerCase() == firstName.toLowerCase() &&
        s.lastName.toLowerCase() == lastName.toLowerCase() &&
        (s.birthDate == null ? '' : isoDate(s.birthDate!)) == stamp)) {
      return ImportIssue(rowNumber, '$firstName $lastName is already enrolled.');
    }
    if (!seen.add(key)) {
      return ImportIssue(rowNumber, '$firstName $lastName appears earlier in this file.');
    }

    return StudentImportRow(
      firstName: firstName,
      lastName: lastName,
      middleName: middleName.isEmpty ? null : middleName,
      educationLevel: division,
      gradeLevel: gradeLevel,
      section: section,
      programId: programId,
      birthDate: birthDate,
      email: email.isEmpty ? null : email,
      phone: phone.isEmpty ? null : phone,
      guardianContacts: guardianName.isEmpty
          ? const []
          : [
              GuardianContact(
                name: guardianName,
                relationship: 'Guardian',
                phone: guardianPhone,
                email: guardianEmail.isEmpty ? null : guardianEmail,
              ),
            ],
    );
  }

  /// Accepts what the export writes ("Senior High School"), what the
  /// database stores ("senior_high"), and the shorthand a registrar
  /// actually types ("SHS", "JHS").
  static EducationLevel? parseDivision(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty) return null;
    for (final level in EducationLevel.values) {
      if (t == level.displayLabel.toLowerCase() || t == level.value) return level;
    }
    return switch (t) {
      'jhs' || 'junior high' || 'high school' => EducationLevel.highSchool,
      'shs' || 'senior high' => EducationLevel.seniorHigh,
      'elem' => EducationLevel.elementary,
      _ => null,
    };
  }

  /// Delegates to [SheetValues.parseDate]: the expense and grade
  /// importers read dates out of the same spreadsheets, and three copies
  /// of this would eventually disagree about 03/07/2012. Kept as a named
  /// method here because "birthday" is what the caller is reading.
  static DateTime? parseBirthday(String text) => SheetValues.parseDate(text);

  static String isoDate(DateTime d) => SheetValues.isoDate(d);
}

/// One validated spreadsheet row, ready for `registerStudent`.
class StudentImportRow {
  final String firstName;
  final String lastName;
  final String? middleName;
  final EducationLevel educationLevel;
  final String gradeLevel;
  final String section;
  final String? programId;
  final DateTime? birthDate;
  final String? email;
  final String? phone;
  final List<GuardianContact> guardianContacts;

  const StudentImportRow({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.educationLevel,
    required this.gradeLevel,
    required this.section,
    required this.programId,
    required this.birthDate,
    required this.email,
    required this.phone,
    required this.guardianContacts,
  });
}
