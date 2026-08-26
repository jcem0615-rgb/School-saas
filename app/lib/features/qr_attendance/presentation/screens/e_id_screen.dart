import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/storage/pdf_image.dart';
import '../../../../core/storage/uploaded_image.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../../student_portal/presentation/controllers/student_controller.dart';

/// CR80 -- the standard ID-card size, 85.6mm x 54mm.
///
/// Laying the card out at true physical size matters: printed to an ID
/// card printer it comes out correct, and printed to an ordinary printer
/// it comes out at the same size on A4, so it can be cut out and it still
/// fits a lanyard holder.
const _cardWidthMm = 85.6;
const _cardHeightMm = 54.0;

/// The card's own geometry, in millimetres, shared by the print and
/// screen layouts so the preview matches what comes out of the printer.
///
/// The proportions are a real credential's rather than a poster's: a
/// coloured header band that names the issuer, a body row of photo,
/// details and code, and a footer strip carrying the number the card is
/// looked up by. The three bands plus their gaps fill the 54mm height
/// with about 1mm to spare, so nothing falls through to a Spacer and
/// leaves a band of dead white above the footer.
const _marginMm = 3.0;
const _headerHeightMm = 8.0;
const _bodyHeightMm = 31.0;
const _footerHeightMm = 11.0;
const _gapMm = 1.5;

/// The photo is a 3:4 rectangle, the shape of an actual ID photo, and it
/// fills the body row. A guard compares a face to a card at arm's
/// length; anything smaller is decoration.
const _photoHeightMm = _bodyHeightMm;
const _photoWidthMm = _photoHeightMm * 3 / 4;

/// Sized to be read by a phone camera at the distance someone actually
/// holds a card. Smaller than the old layout's because it no longer has
/// to carry the card on its own.
const _qrSizeMm = 20.0;

final _longDateFormat = DateFormat('d MMMM y');


/// Everything printed on one person's card, gathered in one place.
///
/// The card is built from two sources -- the account ([AppUser]) and, for
/// students, the registrar's record -- and most fields below are optional
/// because a card still has to print when the school has not filled in
/// its signatories. Rendering "not set" is always better than refusing to
/// print an ID.
class _IdDetails {
  final AppUser user;
  final SchoolBranding branding;
  final StudentSummary? student;

  const _IdDetails({required this.user, required this.branding, this.student});

  bool get isStudent => student != null;

  /// The registrar's record is the authority on a student's name -- it
  /// carries the middle name and is what the school's own paperwork uses.
  String get fullName => student?.fullName ?? user.fullName;

  String? get photoUrl => student?.photoUrl ?? user.photoUrl;

  /// Stands in for a missing photo. A blank grey box reads as a printing
  /// fault; initials read as "no photo on file yet".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  /// The name split the way every credential prints it.
  ///
  /// The registrar's record is the authority: it carries the middle name,
  /// and school paperwork files people by surname. Staff have no such
  /// record, so their account name is split at the last space -- good
  /// enough for a card, and better than printing an empty SURNAME line.
  String get surname => (student?.lastName ?? user.lastName).trim();
  String get givenName => (student?.firstName ?? user.firstName).trim();
  String? get middleName => _clean(student?.middleName);

  /// What this person is to the school, on the header band.
  String get credentialTitle =>
      isStudent ? 'STUDENT IDENTIFICATION CARD' : '${user.role.displayName.toUpperCase()} IDENTIFICATION CARD';

  /// The number the card is looked up by, printed large in the footer.
  /// A student number for a student; for staff the account email is the
  /// only stable handle, and it is not a number, so the footer carries
  /// their role instead and the email moves to the back.
  String? get cardNumber => student?.studentNumber;

  String? get schoolYear => _clean(branding.schoolYear);
  String? get principalName => _clean(branding.principalName);
  String? get directorName => _clean(branding.directorName);

  String? get principalSignatureUrl => _clean(branding.principalSignatureUrl);
  String? get directorSignatureUrl => _clean(branding.directorSignatureUrl);

  String? get birthDate => student?.birthDate == null
      ? null
      : _longDateFormat.format(student!.birthDate!);

  /// The first guardian on the record. Registration collects one, and a
  /// card has room for one -- the rest stay in the student's full record.
  String? get emergencyContact {
    final guardian = student?.guardianContacts.firstOrNull;
    if (guardian == null) return null;
    final relationship = guardian.relationship.isEmpty ? null : guardian.relationship;
    final phone = guardian.phone.isEmpty ? null : guardian.phone;
    return [
      guardian.name,
      if (relationship != null) '($relationship)',
      if (phone != null) '- $phone',
    ].join(' ');
  }

  /// The labelled stack beside the photo.
  ///
  /// Labels above values, in that order and in that many rows, because
  /// that is how an identity document is read: the reader is looking for
  /// one field, and a labelled stack lets them find it without parsing a
  /// sentence. Surname first for the same reason the TOR prints it that
  /// way -- it is what the school's own paperwork sorts by.
  ///
  /// Capped at five rows: six does not fit in 26mm at a size anyone can
  /// read, and a field nobody can read is worse than an absent one.
  List<(String, String)> get frontFields {
    final rows = <(String, String)>[
      ('SURNAME', surname.toUpperCase()),
      ('GIVEN NAME', givenName.toUpperCase()),
      if (middleName != null) ('MIDDLE NAME', middleName!.toUpperCase()),
    ];
    if (isStudent) {
      final classLabel = student!.classLabel.trim();
      if (classLabel.isNotEmpty) rows.add(('GRADE & SECTION', classLabel));
      if (birthDate != null) rows.add(('DATE OF BIRTH', birthDate!));
    } else {
      rows.add(('POSITION', user.role.displayName));
      rows.add(('EMAIL', user.email));
    }
    return rows.take(5).toList();
  }

  /// The rows printed on the back.
  ///
  /// Nothing here repeats the front. Everything the front carries is on
  /// the front; printing it twice costs the space the emergency contact
  /// and the return-if-found notice need, and tells a reader nothing.
  List<(String, String)> get backRows => [
        if (isStudent) ...[
          if (emergencyContact != null) ('EMERGENCY CONTACT', emergencyContact!),
          if (student!.programName != null) ('PROGRAM', student!.programName!),
        ] else
          ('EMAIL', user.email),
        if (branding.addressLine != null) ('SCHOOL ADDRESS', branding.addressLine!),
      ];

  static String? _clean(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
}

/// The user's e-ID: photo, details, and the QR that gates attendance.
///
/// The QR encodes the opaque `qrCode` token, never the raw uid -- the
/// token is what markAttendance resolves, so a photographed ID leaks an
/// attendance handle rather than a user identifier.
class EIdScreen extends ConsumerWidget {
  const EIdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final branding = ref.watch(brandingProvider).valueOrNull ?? SchoolBranding.empty;

    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    // Only students have a registrar record, and only a student may read
    // their own -- watching this for an employee would be a guaranteed
    // permission error, so the subscription is scoped to the role.
    final student =
        user.role == UserRole.student ? ref.watch(myStudentRecordProvider).valueOrNull : null;
    final details = _IdDetails(user: user, branding: branding, student: student);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My School ID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: () => _print(details),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _IdCardFront(details: details)),
          const SizedBox(height: 16),
          Center(child: _IdCardBack(details: details)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _print(details),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print ID'),
          ),
          const SizedBox(height: 8),
          Text(
            'Prints both sides at true card size (85.6 × 54 mm). Send it to '
            'an ID card printer directly, or print on paper and cut along '
            'the border.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (details.schoolYear == null ||
              details.principalName == null ||
              details.directorName == null) ...[
            const SizedBox(height: 12),
            Text(
              'The school year and signatories are blank because an Admin '
              'has not set them yet, under School Branding.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Attendance code', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  SelectableText(user.qrCode),
                  const SizedBox(height: 8),
                  Text(
                    'This code is what the scanner reads. It is not your '
                    'account ID, so a photo of your ID cannot be used to '
                    'sign in as you.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _print(_IdDetails details) async {
    await Printing.layoutPdf(onLayout: (format) => _buildIdCardPdf(details));
  }
}

/// Renders one person's printed ID card, for callers outside the screen.
///
/// The layout is worth testing on its own -- it is the artefact a school
/// actually hands out, and a card that renders blank or throws on a
/// missing signature is not something a widget test of the preview would
/// catch. Takes the same three sources the screen does.
@visibleForTesting
Future<Uint8List> buildIdCardPdf({
  required AppUser user,
  required SchoolBranding branding,
  StudentSummary? student,
}) =>
    _buildIdCardPdf(_IdDetails(user: user, branding: branding, student: student));

/// Builds the card as a two-page PDF at exactly card size: page 1 is the
/// front, page 2 the back.
///
/// Two sides rather than one crowded face -- a CR80 card is 85.6mm wide,
/// and a photo, a QR and the record details on one side would print at a
/// size nobody can read. Duplex or two cuts both work.
///
/// The QR is regenerated here rather than screenshotting the widget, so
/// it prints as crisp vectors at any scale -- a rasterised QR at 54mm is
/// unreliable to scan.
Future<Uint8List> _buildIdCardPdf(_IdDetails details) async {
  final doc = pw.Document();
  final user = details.user;
  final branding = details.branding;

  // Fetched one at a time and each guarded: a logo or photo that fails
  // to load must degrade to its placeholder, never abort the print.
  final logo = branding.hasLogo ? await pdfImage(branding.logoUrl!) : null;
  final photo = details.photoUrl == null ? null : await pdfImage(details.photoUrl!);
  final principalSignature = details.principalSignatureUrl == null
      ? null
      : await pdfImage(details.principalSignatureUrl!);
  final directorSignature = details.directorSignatureUrl == null
      ? null
      : await pdfImage(details.directorSignatureUrl!);

  // No page margin: the header band is full-bleed, the way a real
  // card's is. The margin is applied inside, per band.
  final pageFormat = PdfPageFormat(
    _cardWidthMm * PdfPageFormat.mm,
    _cardHeightMm * PdfPageFormat.mm,
  );

  const mm = PdfPageFormat.mm;
  final brandColor = PdfColor.fromInt(0xFF3D4A7A);

  /// The school's own logo, filling the card behind everything.
  ///
  /// This is what makes a card look issued rather than printed: the
  /// mark of the body that issued it, large and faint, under the data.
  /// Faint enough that the text over it stays the highest-contrast
  /// thing on the card -- a watermark that competes with the name is a
  /// card a guard has to squint at.
  pw.Widget watermark() => logo == null
      ? pw.SizedBox()
      : pw.Positioned.fill(
          child: pw.Center(
            child: pw.Opacity(
              opacity: 0.06,
              child: pw.Image(logo, height: 46 * mm),
            ),
          ),
        );

  pw.Widget label(String text) => pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 3.2,
          color: PdfColors.grey600,
          letterSpacing: 0.4,
          fontWeight: pw.FontWeight.bold,
        ),
        maxLines: 1,
      );

  pw.Widget value(String text, {double size = 6}) => pw.Text(
        text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
        maxLines: 1,
      );

  /// The issuer band. A card says who issued it before it says
  /// anything about the holder.
  pw.Widget header() => pw.Container(
        height: _headerHeightMm * mm,
        width: double.infinity,
        color: brandColor,
        padding: pw.EdgeInsets.symmetric(horizontal: _marginMm * mm, vertical: 1.2 * mm),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 5.4 * mm),
              pw.SizedBox(width: 1.8 * mm),
            ],
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    (branding.schoolName ?? 'School').toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 6.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                    maxLines: 1,
                  ),
                  pw.Text(
                    details.credentialTitle,
                    style: pw.TextStyle(
                      fontSize: 3.4,
                      color: PdfColors.white,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (details.schoolYear != null)
              pw.Text(
                'S.Y. ${details.schoolYear}',
                style: pw.TextStyle(fontSize: 4.5, color: PdfColors.white),
              ),
          ],
        ),
      );

  // ---- front ----
  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (context) => pw.Stack(
        children: [
          watermark(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              header(),
              pw.SizedBox(height: _gapMm * mm),
              pw.Container(
                height: _bodyHeightMm * mm,
                padding: pw.EdgeInsets.symmetric(horizontal: _marginMm * mm),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfPhoto(photo, details.initials),
                    pw.SizedBox(width: 2.5 * mm),
                    // The labelled stack. Spread rather than packed:
                    // the rows fill the photo's height, so the card
                    // reads as laid out rather than as text that ran
                    // out.
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          for (final field in details.frontFields)
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                label(field.$1),
                                value(field.$2, size: 5.5),
                              ],
                            ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 2 * mm),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: user.qrCode,
                      width: _qrSizeMm * mm,
                      height: _qrSizeMm * mm,
                      drawText: false,
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              // The footer carries the number the office looks the card
              // up by, at the size a number on a credential is printed:
              // large, spaced, and the last thing on the card.
              pw.Container(
                height: _footerHeightMm * mm,
                width: double.infinity,
                padding: pw.EdgeInsets.fromLTRB(
                    _marginMm * mm, 1.2 * mm, _marginMm * mm, 1.2 * mm),
                decoration: pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: brandColor, width: 0.8)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          label(details.cardNumber == null ? 'ROLE' : 'STUDENT NUMBER'),
                          pw.Text(
                            details.cardNumber ?? user.role.displayName.toUpperCase(),
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 1.2,
                              color: brandColor,
                            ),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    pw.Text(
                      'Valid only with the school seal',
                      style: const pw.TextStyle(fontSize: 3.2, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  // ---- back ----
  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (context) => pw.Stack(
        children: [
          watermark(),
          pw.Padding(
            padding: pw.EdgeInsets.all(_marginMm * mm),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final row in details.backRows)
                  pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: 1.4 * mm),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [label(row.$1), value(row.$2, size: 5.5)],
                    ),
                  ),
                pw.Spacer(),
                // The line that makes a lost card come back, and the
                // one that makes a borrowed one worthless.
                pw.Text(
                  'This card is the property of '
                  '${branding.schoolName ?? 'the school'} and is '
                  'non-transferable. If found, please return it to the '
                  'school office.',
                  style: const pw.TextStyle(fontSize: 3.6, color: PdfColors.grey700),
                  maxLines: 3,
                ),
                pw.SizedBox(height: 1.5 * mm),
                // Signature lines print whether or not a name is on
                // file, so a card issued before an Admin fills these in
                // can still be signed by hand.
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _pdfSignatory(
                          'Principal', details.principalName, principalSignature),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child:
                          _pdfSignatory('Director', details.directorName, directorSignature),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}


pw.Widget _pdfPhoto(pw.MemoryImage? photo, String initials) => pw.Container(
        width: _photoWidthMm * PdfPageFormat.mm,
        height: _photoHeightMm * PdfPageFormat.mm,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.4, color: PdfColors.grey600),
          borderRadius: pw.BorderRadius.circular(2),
          image: photo == null
              ? null
              : pw.DecorationImage(image: photo, fit: pw.BoxFit.cover),
        ),
        child: photo != null
            ? null
            : pw.Center(
                child: pw.Text(
                  initials,
                  style: pw.TextStyle(fontSize: 16, color: PdfColors.grey600),
                ),
              ),
      );

  /// Signature over name over rule over role -- the order a signed
  /// document is read in.
  ///
  /// The signature sits in a fixed-height box whether or not there is one
  /// to draw. Collapsing the space when a school has not uploaded a scan
  /// would shift the name and rule up and print a visibly different card
  /// from the school next door, and the empty box is exactly the room
  /// somebody needs to sign by hand.
pw.Widget _pdfSignatory(String label, String? name, pw.MemoryImage? signature) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: 5 * PdfPageFormat.mm,
            child: signature == null
                ? null
                : pw.Align(
                    alignment: pw.Alignment.bottomLeft,
                    child: pw.Image(signature, fit: pw.BoxFit.contain),
                  ),
          ),
          pw.Text(
            name ?? ' ',
            style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
            maxLines: 1,
          ),
          pw.Divider(height: 2, thickness: 0.4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 5)),
        ],
      );

/// The card as it appears on screen, at the same proportions, the same
/// bands and the same logo watermark as what the printer produces.
///
/// The preview is not decoration: it is what a student looks at on their
/// phone instead of carrying the printed card, so it has to be the same
/// card. Every size below is in card-millimetres for that reason -- the
/// layout is written once, in the units the printer uses, and the screen
/// scales it.
class _CardShell extends StatelessWidget {
  final SchoolBranding branding;
  final Widget child;

  const _CardShell({required this.branding, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The width cap has to sit OUTSIDE the AspectRatio. Inside it, the
    // AspectRatio has already taken the full width it was offered and
    // passes down tight constraints, which a maxWidth on the Container
    // cannot override -- on a desktop-width window that produced a card
    // the full width of the screen and, at 85.6:54, proportionally
    // enormous.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: AspectRatio(
        aspectRatio: _cardWidthMm / _cardHeightMm,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pxPerMm = constraints.maxWidth / _cardWidthMm;
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(3 * pxPerMm),
                border: Border.all(color: theme.colorScheme.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // The school's own mark, filling the card behind
                  // everything. Faint enough that the name over it stays
                  // the highest-contrast thing on the card.
                  if (branding.hasLogo)
                    Positioned.fill(
                      child: Center(
                        child: Opacity(
                          opacity: 0.06,
                          child: UploadedImage(
                            url: branding.logoUrl!,
                            height: 46 * pxPerMm,
                          ),
                        ),
                      ),
                    ),
                  _CardScale(pxPerMm: pxPerMm, child: child),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Hands the card-millimetre scale down to the faces, so they can size
/// the photo, the QR and every band to the physical dimensions the PDF
/// uses.
class _CardScale extends InheritedWidget {
  final double pxPerMm;

  const _CardScale({required this.pxPerMm, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardScale>()?.pxPerMm ?? 1;

  @override
  bool updateShouldNotify(_CardScale oldWidget) => oldWidget.pxPerMm != pxPerMm;
}

/// The brand colour the header band and the card number are printed in.
/// Fixed rather than themed: a card is a physical object, and it does not
/// change colour because the person holding the phone prefers dark mode.
const _cardBrand = Color(0xFF3D4A7A);

/// A field label: small, spaced, grey, above its value. The pairing is
/// what makes a credential scannable by eye -- a reader looking for one
/// field finds it without reading the others.
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final mm = _CardScale.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: 1.15 * mm,
        letterSpacing: 0.15 * mm,
        fontWeight: FontWeight.bold,
        color: Colors.grey.shade600,
        height: 1.2,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _FieldValue extends StatelessWidget {
  final String text;
  final double sizeMm;
  const _FieldValue(this.text, {this.sizeMm = 1.95});

  @override
  Widget build(BuildContext context) {
    final mm = _CardScale.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: sizeMm * mm,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
        height: 1.15,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The issuer band. A card says who issued it before it says anything
/// about the holder.
class _CardHeader extends StatelessWidget {
  final _IdDetails details;
  const _CardHeader({required this.details});

  @override
  Widget build(BuildContext context) {
    final mm = _CardScale.of(context);
    final branding = details.branding;

    return Container(
      height: _headerHeightMm * mm,
      width: double.infinity,
      color: _cardBrand,
      padding: EdgeInsets.symmetric(horizontal: _marginMm * mm, vertical: 1.2 * mm),
      child: Row(
        children: [
          if (branding.hasLogo) ...[
            UploadedImage(url: branding.logoUrl!, height: 5.4 * mm),
            SizedBox(width: 1.8 * mm),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (branding.schoolName ?? 'School').toUpperCase(),
                  style: TextStyle(
                    fontSize: 2.3 * mm,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  details.credentialTitle,
                  style: TextStyle(
                    fontSize: 1.2 * mm,
                    letterSpacing: 0.18 * mm,
                    color: Colors.white70,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (details.schoolYear != null)
            Text(
              'S.Y. ${details.schoolYear}',
              style: TextStyle(fontSize: 1.6 * mm, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

/// On-screen preview of the printed front.
class _IdCardFront extends StatelessWidget {
  final _IdDetails details;

  const _IdCardFront({required this.details});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      branding: details.branding,
      child: Builder(
        builder: (context) {
          final mm = _CardScale.of(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CardHeader(details: details),
              SizedBox(height: _gapMm * mm),
              SizedBox(
                height: _bodyHeightMm * mm,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: _marginMm * mm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PhotoBox(details: details),
                      SizedBox(width: 2.5 * mm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final field in details.frontFields)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _FieldLabel(field.$1),
                                  _FieldValue(field.$2),
                                ],
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 2 * mm),
                      QrImageView(
                        data: details.user.qrCode,
                        size: _qrSizeMm * mm,
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Container(
                height: _footerHeightMm * mm,
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(_marginMm * mm, 1.2 * mm, _marginMm * mm, 1.2 * mm),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _cardBrand, width: 1)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _FieldLabel(
                              details.cardNumber == null ? 'ROLE' : 'STUDENT NUMBER'),
                          Text(
                            details.cardNumber ?? details.user.role.displayName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 3.5 * mm,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4 * mm,
                              color: _cardBrand,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'Valid only with the school seal',
                      style: TextStyle(fontSize: 1.15 * mm, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The ID photo, at the same 3:4 proportions the printer uses. Falls back
/// to initials rather than an empty box, which reads as a printing fault.
class _PhotoBox extends StatelessWidget {
  final _IdDetails details;

  const _PhotoBox({required this.details});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mm = _CardScale.of(context);
    final url = details.photoUrl;

    final initials = Text(
      details.initials,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 6 * mm,
        color: Colors.grey.shade500,
      ),
    );

    return Container(
      width: _photoWidthMm * mm,
      height: _photoHeightMm * mm,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(0.6 * mm),
        border: Border.all(color: _cardBrand.withValues(alpha: 0.45), width: 0.4 * mm),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null
          ? initials
          : UploadedImage(
              url: url,
              fit: BoxFit.cover,
              width: _photoWidthMm * mm,
              height: _photoHeightMm * mm,
              fallback: initials,
            ),
    );
  }
}

/// On-screen preview of the printed back: the details, the return notice
/// and the signatories.
class _IdCardBack extends StatelessWidget {
  final _IdDetails details;

  const _IdCardBack({required this.details});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      branding: details.branding,
      child: Builder(
        builder: (context) {
          final mm = _CardScale.of(context);

          return Padding(
            padding: EdgeInsets.all(_marginMm * mm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in details.backRows)
                  Padding(
                    padding: EdgeInsets.only(bottom: 1.4 * mm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_FieldLabel(row.$1), _FieldValue(row.$2)],
                    ),
                  ),
                const Spacer(),
                Text(
                  'This card is the property of '
                  '${details.branding.schoolName ?? 'the school'} and is '
                  'non-transferable. If found, please return it to the '
                  'school office.',
                  style: TextStyle(fontSize: 1.3 * mm, color: Colors.grey.shade700, height: 1.25),
                  maxLines: 3,
                ),
                SizedBox(height: 1.5 * mm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _Signatory(
                        label: 'Principal',
                        name: details.principalName,
                        signatureUrl: details.principalSignatureUrl,
                      ),
                    ),
                    SizedBox(width: 3 * mm),
                    Expanded(
                      child: _Signatory(
                        label: 'Director',
                        name: details.directorName,
                        signatureUrl: details.directorSignatureUrl,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Signatory extends StatelessWidget {
  final String label;
  final String? name;
  final String? signatureUrl;

  const _Signatory({required this.label, required this.name, this.signatureUrl});

  @override
  Widget build(BuildContext context) {
    final mm = _CardScale.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same fixed height as the print layout, so the preview does not
        // promise a card that sits differently on paper, and so a school
        // with one signature on file and not the other still gets two
        // columns that line up.
        SizedBox(
          height: 5 * mm,
          width: double.infinity,
          child: signatureUrl == null
              ? null
              : Align(
                  alignment: Alignment.bottomLeft,
                  child: UploadedImage(url: signatureUrl!, fit: BoxFit.contain),
                ),
        ),
        Container(height: 0.25 * mm, color: Colors.grey.shade700),
        SizedBox(height: 0.5 * mm),
        _FieldValue(name ?? ' ', sizeMm: 1.7),
        _FieldLabel(label.toUpperCase()),
      ],
    );
  }
}
