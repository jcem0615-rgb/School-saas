import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/core/constants/education_level.dart';
import 'package:logicclass/features/payments/domain/entities/assessment.dart';
import 'package:logicclass/features/payments/domain/entities/discount.dart';
import 'package:logicclass/features/payments/domain/entities/fee_structure.dart';
import 'package:logicclass/features/payments/domain/entities/subsidy.dart';
import 'package:logicclass/features/payments/domain/usecases/fee_usecases.dart';
import 'package:logicclass/features/registrar_portal/domain/entities/student_summary.dart';
import 'package:logicclass/features/reports/domain/entities/report_period.dart';
import 'package:logicclass/features/reports/domain/usecases/discounts_report.dart';
import 'package:logicclass/features/reports/domain/usecases/subsidy_claims_report.dart';

/// A grant is not a discount, and the whole feature is that distinction.
///
/// One is money the school gave away and will never see; the other is
/// money the school is owed and has to bill for. Confusing them makes the
/// year-end figures wrong in both directions at once -- overstating what
/// the school absorbed and losing the claim.
void main() {
  const fees = [
    FeeItem(label: 'Tuition Fee', amount: 20000, category: FeeCategory.tuition),
    FeeItem(label: 'Miscellaneous Fee', amount: 4000, category: FeeCategory.miscellaneous),
  ];

  Subsidy voucher({
    double amount = 6500,
    String reference = 'QVR-2026-0099142',
    SubsidyProgramme programme = SubsidyProgramme.shsVoucher,
  }) =>
      Subsidy(
        programme: programme,
        referenceNumber: reference,
        amount: amount,
        recordedByName: 'Joel Bautista',
      );

  Discount sibling({double amount = 2000}) => Discount(
        kind: DiscountKind.sibling,
        label: 'Sibling discount',
        amount: amount,
        approvedByName: 'Grace Mendoza',
      );

  Assessment assessed({
    List<Discount> discounts = const [],
    List<Subsidy> subsidies = const [],
    DateTime? voidedAt,
    String studentId = 'stu1',
  }) =>
      Assessment(
        id: 'a1',
        studentId: studentId,
        studentName: 'Trisha Mercado',
        schoolYear: '2026-2027',
        items: fees,
        discounts: discounts,
        subsidies: subsidies,
        assessedByName: 'Joel Bautista',
        assessedAt: DateTime(2026, 6, 15),
        voidedAt: voidedAt,
      );

  group('what the family is left with', () {
    test('a grant comes off the bill like a discount does', () {
      expect(assessed(subsidies: [voucher()]).total, 17500);
    });

    test('a discount and a grant both come off, and stay countable apart', () {
      final assessment = assessed(discounts: [sibling()], subsidies: [voucher()]);
      expect(assessment.grossTotal, 24000);
      expect(assessment.discountTotal, 2000);
      expect(assessment.subsidyTotal, 6500);
      expect(assessment.total, 15500);
    });

    test('a grant covering everything left charges the family nothing', () {
      final assessment =
          assessed(discounts: [sibling()], subsidies: [voucher(amount: 22000)]);
      expect(assessment.total, 0);
    });
  });

  group('what is refused before it is recorded', () {
    test('a grant with no certificate number', () {
      // The one that matters. A grant the school cannot cite a
      // certificate for is one it cannot bill for -- so the family has
      // simply been charged less and nobody will notice until the year
      // is reconciled.
      expect(
        checkSubsidies([voucher(reference: '   ')], 24000)?.message,
        contains('certificate or voucher number'),
      );
    });

    test('one certificate claimed twice on the same assessment', () {
      // PEAC rejects the second, after the family has been charged as
      // though both were coming.
      expect(
        checkSubsidies([voucher(), voucher()], 24000)?.message,
        contains('appears twice'),
      );
    });

    test('the same number under two different programmes is allowed', () {
      // Different grantors number independently; an ESC certificate and
      // a city scholarship can collide by coincidence.
      expect(
        checkSubsidies([
          voucher(programme: SubsidyProgramme.esc, amount: 5000),
          voucher(programme: SubsidyProgramme.other, amount: 5000),
        ], 24000),
        isNull,
      );
    });

    test('more granted than is left after discounts', () {
      // Checked against what remains, not the gross: a student with a
      // 2,000 sibling discount has 22,000 chargeable, not 24,000.
      expect(
        checkSubsidies([voucher(amount: 23000)], 22000)?.message,
        contains('the whole of what is left and no more'),
      );
    });

    test('a grant covering exactly what is left is allowed', () {
      expect(checkSubsidies([voucher(amount: 22000)], 22000), isNull);
    });

    test('nothing at all is fine', () {
      expect(checkSubsidies(const [], 24000), isNull);
    });
  });

  group('the messages actually say the numbers', () {
    // Written after every validation message in this file was found to
    // be printing a literal ${...} to the user: the interpolations had
    // been escaped, so a bursar over-granting a discount was told "The
    // discounts come to \${given.toStringAsFixed(2)}". Every test here
    // passed anyway, because they all asserted on the static half of the
    // sentence with `contains`. These assert on the half that varies.
    test('a duplicate certificate is named', () {
      expect(
        checkSubsidies([voucher(), voucher()], 24000)?.message,
        contains('QVR-2026-0099142'),
      );
    });

    test('an over-grant states both figures', () {
      final message = checkSubsidies([voucher(amount: 23000)], 22000)!.message;
      expect(message, contains('23000.00'));
      expect(message, contains('22000.00'));
    });

    test('no message anywhere leaks a raw interpolation', () {
      for (final message in [
        checkSubsidies([voucher(reference: ' ')], 24000)?.message,
        checkSubsidies([voucher(), voucher()], 24000)?.message,
        checkSubsidies([voucher(amount: 99000)], 22000)?.message,
        checkDiscounts([sibling(amount: 99000)], 24000)?.message,
        checkInstallments(const [], 100)?.message,
      ]) {
        if (message == null) continue;
        expect(message, isNot(contains(r'\$')),
            reason: 'an escaped interpolation reaches the user as source code');
        expect(message, isNot(contains('toStringAsFixed')));
      }
    });
  });

  group('how the line reads to a family', () {
    test('names the programme and the number it is claimed against', () {
      expect(
        voucher().displayLine,
        'SHS voucher · QVR / voucher no. QVR-2026-0099142',
      );
    });

    test('an ESC grant uses the word ESC uses', () {
      expect(
        voucher(programme: SubsidyProgramme.esc).displayLine,
        startsWith('ESC grant · ESC certificate no.'),
      );
    });
  });

  group('the two reports do not double count', () {
    final period = ReportPeriod(DateTime(2026, 6, 1), DateTime(2026, 12, 31));

    final student = StudentSummary(
      id: 'stu1',
      studentNumber: '2026-00099',
      firstName: 'Trisha',
      lastName: 'Mercado',
      gradeLevel: 'Grade 11',
      section: 'STEM-A',
      educationLevel: EducationLevel.seniorHigh,
      status: StudentStatus.enrolled,
      balance: 0,
      enrollmentDate: DateTime(2026, 6, 1),
    );

    test('a grant is not counted as money the school gave away', () {
      // The whole reason a subsidy is not a DiscountKind. Counting the
      // voucher here would tell a board the school absorbed 8,500 when
      // it absorbed 2,000.
      final table = DiscountsReport.build(
        period: period,
        students: [student],
        assessments: [assessed(discounts: [sibling()], subsidies: [voucher()])],
      );
      expect(table.headline.first.value, contains('2,000'));
      expect(table.rows.first.cells.first, 'Sibling discount');
    });

    test('a discount is not billed to DepEd', () {
      final table = SubsidyClaimsReport.build(
        period: period,
        students: [student],
        assessments: [assessed(discounts: [sibling()], subsidies: [voucher()])],
      );
      expect(table.headline.first.value, contains('6,500'));
      expect(table.rows.first.cells[4], 'QVR-2026-0099142');
    });

    test('a voided assessment is billed to nobody', () {
      final table = SubsidyClaimsReport.build(
        period: period,
        students: [student],
        assessments: [
          assessed(subsidies: [voucher()], voidedAt: DateTime(2026, 7, 1)),
        ],
      );
      expect(table.rows, isEmpty);
    });

    test('one student with two grants is two claims', () {
      // The school bills per certificate, to two grantors.
      final table = SubsidyClaimsReport.build(
        period: period,
        students: [student],
        assessments: [
          assessed(subsidies: [
            voucher(programme: SubsidyProgramme.esc, reference: 'ESC-1', amount: 5000),
            voucher(reference: 'QVR-2', amount: 6500),
          ]),
        ],
      );
      // Two claims plus the total row.
      expect(table.rows.length, 3);
      expect(table.headline[1].value, '1', reason: 'but only one grantee');
    });
  });
}
