import 'package:flutter_test/flutter_test.dart';

import 'package:logicclass/features/admin_portal/domain/entities/school_branding.dart';
import 'package:logicclass/features/payroll/domain/entities/payslip.dart';
import 'package:logicclass/features/payroll/presentation/documents/payslip_pdf.dart';

/// The payslip renders.
///
/// Thin on assertions and worth keeping: the PDF layer is where this
/// codebase has repeatedly found real defects, and a payslip that throws
/// on print is the failure a school finds on payday with forty people
/// waiting.
void main() {
  const branding = SchoolBranding(
    schoolName: 'Demo Academy of Bulacan',
    addressLine: 'Malolos, Bulacan',
    directorName: 'Joel Bautista',
  );

  Payslip slip({int missingTimeOut = 0}) => Payslip(
        employeeUid: 'u_faculty',
        employeeName: 'Maria Santos',
        periodFrom: '2026-06-01',
        periodTo: '2026-06-30',
        earnings: const [
          PayslipLine(label: 'Basic pay', amount: 32000, basis: 'Monthly salary'),
          PayslipLine(label: 'Allowance', amount: 2000),
        ],
        deductions: const [
          PayslipLine(label: 'SSS', amount: 1350, basis: 'SSS Circular 2025-006'),
          PayslipLine(label: 'PhilHealth', amount: 800),
          PayslipLine(label: 'Pag-IBIG', amount: 200),
          PayslipLine(label: 'Withholding tax', amount: 1030.05),
        ],
        basicPay: 32000,
        grossPay: 34000,
        totalDeductions: 3380.05,
        netPay: 30619.95,
        employerContributions: 3600,
        daysWorked: 21,
        daysAbsent: 1,
        daysLate: 2,
        daysMissingTimeOut: missingTimeOut,
      );

  test('a payslip renders to a PDF', () async {
    final bytes = await PayslipPdf.build(
      payslip: slip(),
      branding: branding,
      on: DateTime(2026, 6, 30),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('a payslip with unknown hours still prints, and says so', () async {
    // The person holding it should know before they bank on it.
    final bytes = await PayslipPdf.build(
      payslip: slip(missingTimeOut: 3),
      branding: branding,
      on: DateTime(2026, 6, 30),
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(slip(missingTimeOut: 3).hoursAreIncomplete, isTrue);
  });

  test('the file name is safe to write to a disk', () {
    expect(
      PayslipPdf.fileName(slip()),
      'payslip-maria-santos-2026-06-01.pdf',
    );
  });
}
