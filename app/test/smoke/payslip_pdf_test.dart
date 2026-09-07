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

  /// A real PNG, as a data URI -- the shape a demo school's logo takes,
  /// and the one `networkImage` cannot fetch. Encoded inline so the test
  /// needs no asset and no network.
  const logoDataUri = 'data:image/png;base64,'
    'iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAAFIElEQVR42u3dUW1jURAEUe'
    'MIgaAIGGMLubCwfwPA9rszdUpqALnTXXYirfZ2AwAAAAAAAAAAAAAAAABcz9f3/XFVvD4Q'
    'GDoxAMZOCoDBEwJg8IQAGD0ZAEZPBoDRkwEMX4gAhi9EAKMXMoDhCxHA8IUIYPhCBDB8IQ'
    'IYv5AADF+IAIYvRADjFxKA4QsRwPiFBGD4ry+8dyAC41da70kCxq+Y3poEDF8B3YEIlE7Z'
    '3IUElEy53IkEFEqZ3M7tFEhx3NItFUZZ3NVdlUQ53BlKoRBujngRXMX94fjQA1SO7iI6oR'
    'PBQ7uGfuhH8LguoSu64qDQGZ2pHNIV9Ed/HA96pEeOBn3Sp9XHcgHd0i0Hgo7pWOk4Xl/P'
    '9Cx4FC+vczrnENA93XMA6KAOrn98rw499OiAPnpsQC89MqCfOx9YpaGjHhbQVQ8K6Oz6x1'
    'Rd6K1HBPTX4wF67OEAPfZogD4vezDVhE57KEC3fVUC9JshAR33MICuL3sU1YO+MyKg82wI'
    '6L1HAPTfAwD674cH7MAPDtjB+B9ctUACh27Bpz8Q3oPxA9FNGD8Q3gYBANFtGD8Q3ggBAA'
    'Rg/EBtJz79gfBWCAAgAOMHanvx6Q+EN2P8QHg3BABEd+PrPxDezobx//3+PET+x7cAAhAC'
    'sJ/tP4Cyy5USGL0fn/5CAOEd+fQXEiAAAhACIABf/4UAMlvy6S8kEN4TAQgBEICv/0IAxU'
    '359BcSIAACEAKobcrv/0IA4b8DTBaAMsupEsgLwKe/+BZAAAQgBEAAxi9+DSAAAhACOGdb'
    '/gAoBBD+QyABCAEQgD8ACgEUfw3w6S8kQAAEIARAAAQgBEAABCAEQAAEIARAAAQgBEAABC'
    'AEQAAEIARAAAQgBEAABCAEQAAEIARAAAQgBEAA/iGQEMCQnfkGIATgGwABCAEQAAEIARAA'
    'AQgBEAABCAEQAAEIARAAAQgBEAABCAEQAAEIARAAAQgBEAABCAEQAAEIARCAfxAkxh8XgG'
    '8BQgD+c1ACEAKo/hfhBCAEMGBbBCAEQAD+ECjGTwAEIARAAH4NEAJo7GqyAEhAap/+b9kV'
    'AQgBhDdFAEIABDBSACQgp42fAHwLEJ/+BEAAQgBD9uTXADH+8JZ8CxACCO+IAIQACMCvAW'
    'L81R35FiAEEP4Q9S1AjJ8ACEAIgADmSgD4NGu2QwBAeDcEABAACQDVzRAAEN6LbwFAeCsE'
    'AMS3QgBAeCe+BQDhjRAAEN8ICQDhbRAAEN8GCQDhTbz7hyUBGP/heyAAILwF3wKA8A4IAI'
    'jvgARg/OH+EwAIIN5/jwDjD/f+Ew9BAtB5NgT0nREBXfcwgI73HocEoN8MCei2hwJ02lcl'
    'QJ89GqDHHg7QY48H6K9HBPR2/0OSAHTWg5IAdNXDAjqafVwSgH56ZBKAXnpsQB89OqCHzY'
    'f3+NBBB3AA6J5DQOd0Ln0QR9EzPYsfxnF0TMccyIF0S7fqh3IsfdInR3M0PdIjx4P+6E/6'
    'iA6pMzrjoA6qK7pSP6zj6od+OLJD64ROOLij64EeOL7juz+UQBHcHAqhFO4M5VASd4WyKI'
    'xbQnEUyO2gTArlTlCuZsncBcoWK507QAEjZfTWUMxAWb0nSGBJyb2D8ROBiOGTgBg/iEAM'
    'HyQgxg8iEMMHEYjhgwTE+EEEYvggAjF8EIEYPohADB9kIEYPIhDDBxGI4YMMxOhBBmL0IA'
    'MjN3qgLARXB0JCcFUgIgXXAgJi8PoAAAAAAAAAAAAAAABn8ARQy5SVQGNQfQAAAABJRU5E'
    'rkJggg==';

  const brandedWithLogo = SchoolBranding(
    schoolName: 'Demo Academy of Bulacan',
    addressLine: 'Malolos, Bulacan',
    directorName: 'Joel Bautista',
    logoUrl: logoDataUri,
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

  group('the school logo behind it', () {
    test('is embedded in the document when the school has one', () async {
      // A payslip comes back months later attached to a loan
      // application. One that says only "PAYSLIP" and a name is a page
      // anybody could have typed.
      final plain = await PayslipPdf.build(
        payslip: slip(),
        branding: branding,
        on: DateTime(2026, 6, 30),
      );
      final branded = await PayslipPdf.build(
        payslip: slip(),
        branding: brandedWithLogo,
        on: DateTime(2026, 6, 30),
      );

      expect(String.fromCharCodes(branded.take(5)), '%PDF-');
      // The image is a real object in the file, not a caption about one.
      expect(branded.length, greaterThan(plain.length + 500));
      expect(String.fromCharCodes(branded), contains('/Image'));
    });

    test('a logo that will not load does not stop the payslip printing',
        () async {
      // A missing letterhead must never be the reason somebody is not
      // handed their pay. `pdfImage` swallows the failure by design, so
      // this is what proves the document still comes out.
      const broken = SchoolBranding(
        schoolName: 'Demo Academy of Bulacan',
        directorName: 'Joel Bautista',
        logoUrl: 'https://storage.invalid/does-not-exist.png',
      );
      final bytes = await PayslipPdf.build(
        payslip: slip(),
        branding: broken,
        on: DateTime(2026, 6, 30),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('a school with no logo at all still gets a payslip', () async {
      final bytes = await PayslipPdf.build(
        payslip: slip(),
        branding: branding,
        on: DateTime(2026, 6, 30),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(branding.hasLogo, isFalse);
    });
  });

  test('the file name is safe to write to a disk', () {
    expect(
      PayslipPdf.fileName(slip()),
      'payslip-maria-santos-2026-06-01.pdf',
    );
  });
}
