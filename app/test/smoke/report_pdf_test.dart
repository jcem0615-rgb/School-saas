import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/reports/domain/usecases/enrollment_report.dart';
import 'package:logicclass/features/reports/presentation/documents/report_pdf.dart';

/// The printed report builds.
///
/// Thin on assertions and worth keeping anyway: the PDF layer is where
/// this codebase has repeatedly found real defects -- a signature that
/// silently did not load, a peso sign Helvetica dropped without
/// complaint, a const constructor that would not compile. A builder
/// that throws on a totals row is exactly the failure a school finds by
/// pressing Print in front of somebody.
void main() {
  test('a report renders to a PDF', () async {
    final students = [
      for (var i = 0; i < 6; i++)
        StudentSummary(
          id: 's$i',
          studentNumber: '2026-0000$i',
          firstName: 'Student',
          lastName: '$i',
          educationLevel: i < 3 ? EducationLevel.highSchool : EducationLevel.seniorHigh,
          gradeLevel: i < 3 ? 'Grade 10' : 'Grade 11',
          section: i.isEven ? 'Rizal' : 'Bonifacio',
          status: i == 5 ? StudentStatus.transferredOut : StudentStatus.enrolled,
          balance: 0,
          enrollmentDate: DateTime(2026, 6, 1),
        ),
    ];

    final bytes = await ReportPdf.build(
      table: EnrollmentReport.build(students),
      branding: const SchoolBranding(
        schoolName: 'Demo Academy of Bulacan',
        addressLine: 'Malolos, Bulacan',
        schoolYear: '2026-2027',
      ),
      preparedByName: 'Joel Bautista',
      on: DateTime(2026, 8, 27, 9, 15),
    );

    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.take(5)),
      startsWith('%PDF'),
      reason: 'the bytes have to be a PDF, not an error page',
    );
  });
}
