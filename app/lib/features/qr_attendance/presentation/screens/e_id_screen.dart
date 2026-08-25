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

/// Photo and QR sizes, in mm, shared by the print and screen layouts so
/// the preview matches what comes out of the printer.
///
/// These are the two things a card is checked with -- a guard compares
/// the face, a scanner reads the code -- so they get the space, and
/// everything else fits around them. The photo is a 3:4 rectangle, the
/// shape of an actual ID photo, rather than a circle: same height, more
/// of the face.
/// Sized to fill the body of the card. They sit on their own row, photo
/// left and QR right, with the name spanning the full width beneath --
/// squeezing all three onto one row left the name in a ~22mm column,
/// wrapping "Miguel Torres" onto two lines to make room for a QR that
/// was still too small.
const _photoHeightMm = 27.0;
const _photoWidthMm = _photoHeightMm * 3 / 4;
const _qrSizeMm = 27.0;

final _dateFormat = DateFormat.yMMMd();

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

  /// The one line under the name on the front: what this person is to the
  /// school. For a student that is their year and section, which is what
  /// anyone checking the card actually wants; for everyone else, the role.
  String get frontSubtitle => user.role.displayName;

  /// The class, said once. `classLabel` collapses "Grade 10" and
  /// "Grade 10 - Rizal" into one, which on a card 85.6mm wide is the
  /// difference between fitting on the line and being ellipsised.
  String? get frontDetail => student?.classLabel;

  String? get schoolYear => _clean(branding.schoolYear);
  String? get principalName => _clean(branding.principalName);
  String? get directorName => _clean(branding.directorName);

  String? get principalSignatureUrl => _clean(branding.principalSignatureUrl);
  String? get directorSignatureUrl => _clean(branding.directorSignatureUrl);

  String? get birthDate =>
      student?.birthDate == null ? null : _dateFormat.format(student!.birthDate!);

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
      if (phone != null) '· $phone',
    ].join(' ');
  }

  /// The rows printed on the back, in order.
  ///
  /// Nothing here repeats the front. The name, role, year, section and
  /// school year are all on the face of the card; printing them again on
  /// the back cost the space that the photo and QR now use, and gave a
  /// reader nothing they could not already see.
  List<(String, String)> get backRows => [
        if (isStudent) ...[
          ('Student No.', student!.studentNumber),
          if (birthDate != null) ('Birthday', birthDate!),
          if (emergencyContact != null) ('Emergency Contact', emergencyContact!),
        ] else
          ('Email', user.email),
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
    await Printing.layoutPdf(onLayout: (format) => _buildPdf(details));
  }

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
  Future<Uint8List> _buildPdf(_IdDetails details) async {
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

    final pageFormat = PdfPageFormat(
      _cardWidthMm * PdfPageFormat.mm,
      _cardHeightMm * PdfPageFormat.mm,
      marginAll: 3 * PdfPageFormat.mm,
    );

    pw.Widget watermark() => logo == null
        ? pw.SizedBox()
        : pw.Positioned.fill(
            child: pw.Center(
              // Visible enough to identify the school, faint enough not to
              // fight the text over it.
              child: pw.Opacity(
                opacity: 0.08,
                child: pw.Image(logo, height: 38 * PdfPageFormat.mm),
              ),
            ),
          );

    pw.Widget header() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 7 * PdfPageFormat.mm),
              pw.SizedBox(width: 3),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    branding.schoolName ?? 'School ID',
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                  if (branding.addressLine != null)
                    pw.Text(
                      branding.addressLine!,
                      style: const pw.TextStyle(fontSize: 4.5),
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            if (details.schoolYear != null)
              pw.Text('SY ${details.schoolYear}', style: const pw.TextStyle(fontSize: 5)),
          ],
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
                pw.Divider(height: 5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _pdfPhoto(photo, details.initials),
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: user.qrCode,
                      width: _qrSizeMm * PdfPageFormat.mm,
                      height: _qrSizeMm * PdfPageFormat.mm,
                      drawText: false,
                    ),
                  ],
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        details.fullName,
                        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        maxLines: 1,
                      ),
                      pw.Text(
                        details.frontDetail == null
                            ? details.frontSubtitle
                            : '${details.frontSubtitle} · ${details.frontDetail}',
                        style: const pw.TextStyle(fontSize: 6.5),
                        maxLines: 1,
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
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: details.backRows
                        .map(
                          (row) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 2.5),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(
                                  width: 24 * PdfPageFormat.mm,
                                  child: pw.Text(row.$1, style: const pw.TextStyle(fontSize: 6)),
                                ),
                                pw.Expanded(
                                  child: pw.Text(
                                    row.$2,
                                    style:
                                        pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                // Signature lines print whether or not a name is on file,
                // so a card issued before an Admin fills these in can still
                // be signed by hand.
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _pdfSignatory(
                          'Principal', details.principalName, principalSignature),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Expanded(
                      child: _pdfSignatory('Director', details.directorName, directorSignature),
                    ),
                  ],
                ),
              ],
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
}

/// Shared chrome for both on-screen card faces, so the preview keeps the
/// same proportions and logo watermark as what the printer produces.
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
            // Everything inside is sized in card-millimetres so the
            // preview scales with the card instead of drifting from the
            // print at different widths.
            final pxPerMm = constraints.maxWidth / _cardWidthMm;
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  if (branding.hasLogo)
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.07,
                        child: Image.network(
                          branding.logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.all(3 * pxPerMm),
                    child: _CardScale(pxPerMm: pxPerMm, child: child),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Hands the card-millimetre scale down to the faces, so they can size the
/// photo and QR to the same physical dimensions the PDF uses.
class _CardScale extends InheritedWidget {
  final double pxPerMm;

  const _CardScale({required this.pxPerMm, required super.child});

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardScale>()?.pxPerMm ?? 1;

  @override
  bool updateShouldNotify(_CardScale oldWidget) => oldWidget.pxPerMm != pxPerMm;
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
          final theme = Theme.of(context);
          final branding = details.branding;
          final mm = _CardScale.of(context);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (branding.hasLogo)
                    Padding(
                      padding: EdgeInsets.only(right: 1.5 * mm),
                      child: Image.network(
                        branding.logoUrl!,
                        height: 7 * mm,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          branding.schoolName ?? 'School ID',
                          style: theme.textTheme.labelMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (branding.addressLine != null)
                          Text(
                            branding.addressLine!,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 1.6 * mm),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (details.schoolYear != null)
                    Text(
                      'SY ${details.schoolYear}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 1.8 * mm),
                    ),
                ],
              ),
              Divider(height: 2 * mm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PhotoBox(details: details),
                  QrImageView(
                    data: details.user.qrCode,
                    size: _qrSizeMm * mm,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
              // Full width, under both: the name is the longest thing on
              // the card and the only one that has to stay on one line.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      details.fullName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 4 * mm,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      details.frontDetail == null
                          ? details.frontSubtitle
                          : '${details.frontSubtitle} · ${details.frontDetail}',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 2.4 * mm),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

    return Container(
      width: _photoWidthMm * mm,
      height: _photoHeightMm * mm,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(0.7 * mm),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null
          ? Text(
              details.initials,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 6 * mm),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: _photoWidthMm * mm,
              height: _photoHeightMm * mm,
              errorBuilder: (_, __, ___) => Text(
                details.initials,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 6 * mm),
              ),
            ),
    );
  }
}

/// On-screen preview of the printed back: the details and the signatories.
class _IdCardBack extends StatelessWidget {
  final _IdDetails details;

  const _IdCardBack({required this.details});

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      branding: details.branding,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final mm = _CardScale.of(context);
          final labelStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 2.3 * mm);
          final valueStyle = theme.textTheme.bodySmall?.copyWith(
            fontSize: 2.3 * mm,
            fontWeight: FontWeight.bold,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: details.backRows
                      .map(
                        (row) => Padding(
                          padding: EdgeInsets.only(bottom: mm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 24 * mm, child: Text(row.$1, style: labelStyle)),
                              Expanded(
                                child:
                                    Text(row.$2, style: valueStyle, overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
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
    final theme = Theme.of(context);
    final mm = _CardScale.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Same fixed height as the print layout, so the preview does not
        // promise a card that sits differently on paper.
        SizedBox(
          height: 5 * mm,
          width: double.infinity,
          child: signatureUrl == null
              ? null
              : Align(
                  alignment: Alignment.bottomLeft,
                  child: Image.network(
                    signatureUrl!,
                    fit: BoxFit.contain,
                    // A signature that will not load leaves the blank
                    // line, which is still a printable card.
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
        ),
        Text(
          name ?? ' ',
          style: theme.textTheme.bodySmall
              ?.copyWith(fontSize: 2.3 * mm, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        Divider(height: mm),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 2 * mm)),
      ],
    );
  }
}
