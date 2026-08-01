import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/constants/user_roles.dart';
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

final _dateFormat = DateFormat.yMMMd();

/// Everything printed on one person's card, gathered in one place.
///
/// The card is built from two sources -- the account ([AppUser]) and, for
/// students, the registrar's record -- and every field below is optional
/// because a card still has to print when the school has not filled in
/// its signatories or a student has no birth date on file. Rendering
/// "not set" is always better than refusing to print an ID.
class _IdDetails {
  final AppUser user;
  final SchoolBranding branding;
  final StudentSummary? student;

  const _IdDetails({required this.user, required this.branding, this.student});

  bool get isStudent => student != null;

  /// The registrar's record is the authority on a student's name -- it
  /// carries the middle name and is what the school's own paperwork uses.
  String get fullName => student?.fullName ?? user.fullName;

  String? get gradeLevel => student?.gradeLevel;
  String? get section => student?.section;
  String? get schoolYear => _clean(branding.schoolYear);
  String? get principalName => _clean(branding.principalName);
  String? get directorName => _clean(branding.directorName);

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

  /// The rows printed on the back of the card, in order, skipping
  /// anything the school has not recorded.
  List<(String, String)> get backRows => [
        if (isStudent) ('Student No.', student!.studentNumber),
        if (gradeLevel != null) (student!.isCollege ? 'Year Level' : 'Grade Level', gradeLevel!),
        if (section != null) ('Section', section!),
        if (schoolYear != null) ('School Year', schoolYear!),
        if (birthDate != null) ('Birthday', birthDate!),
        if (emergencyContact != null) ('Emergency Contact', emergencyContact!),
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
          if (details.isStudent &&
              (details.schoolYear == null ||
                  details.principalName == null ||
                  details.directorName == null)) ...[
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
  /// and a photo, a QR and eight lines of detail on one side would print
  /// at a size nobody can read. Duplex or two cuts both work.
  ///
  /// The QR is regenerated here rather than screenshotting the widget, so
  /// it prints as crisp vectors at any scale -- a rasterised QR at 54mm is
  /// unreliable to scan.
  Future<Uint8List> _buildPdf(_IdDetails details) async {
    final doc = pw.Document();
    final user = details.user;
    final branding = details.branding;

    // Only fetch the logo when there is one; a failed network image would
    // otherwise abort the whole print.
    pw.MemoryImage? logo;
    if (branding.hasLogo) {
      try {
        logo = await networkImage(branding.logoUrl!) as pw.MemoryImage;
      } catch (_) {
        logo = null;
      }
    }

    final pageFormat = PdfPageFormat(
      _cardWidthMm * PdfPageFormat.mm,
      _cardHeightMm * PdfPageFormat.mm,
      marginAll: 4 * PdfPageFormat.mm,
    );

    pw.Widget watermark() => logo == null
        ? pw.SizedBox()
        : pw.Positioned.fill(
            child: pw.Center(
              // Visible enough to identify the school, faint enough not to
              // fight the text over it.
              child: pw.Opacity(
                opacity: 0.08,
                child: pw.Image(logo, height: 40 * PdfPageFormat.mm),
              ),
            ),
          );

    pw.Widget header() => pw.Row(
          children: [
            if (logo != null) ...[
              pw.Image(logo, height: 8 * PdfPageFormat.mm),
              pw.SizedBox(width: 4),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    branding.schoolName ?? 'School ID',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    maxLines: 1,
                  ),
                  if (branding.addressLine != null)
                    pw.Text(branding.addressLine!, style: const pw.TextStyle(fontSize: 5)),
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
                pw.Divider(height: 4),
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 3,
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              details.fullName,
                              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.SizedBox(height: 1),
                            pw.Text(user.role.displayName, style: const pw.TextStyle(fontSize: 7)),
                            if (details.gradeLevel != null)
                              pw.Text(
                                '${details.gradeLevel} · ${details.section}',
                                style: const pw.TextStyle(fontSize: 7),
                              ),
                            pw.SizedBox(height: 4),
                            pw.Text(user.email, style: const pw.TextStyle(fontSize: 5)),
                            pw.Text('ID ${user.qrCode}', style: const pw.TextStyle(fontSize: 5)),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: user.qrCode,
                        width: 22 * PdfPageFormat.mm,
                        height: 22 * PdfPageFormat.mm,
                        drawText: false,
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
                pw.Text(
                  details.fullName,
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
                ),
                pw.Divider(height: 4),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: details.backRows
                        .map(
                          (row) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 1.5),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.SizedBox(
                                  width: 24 * PdfPageFormat.mm,
                                  child: pw.Text(
                                    row.$1,
                                    style: const pw.TextStyle(fontSize: 5.5),
                                  ),
                                ),
                                pw.Expanded(
                                  child: pw.Text(
                                    row.$2,
                                    style: pw.TextStyle(
                                        fontSize: 5.5, fontWeight: pw.FontWeight.bold),
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
                    pw.Expanded(child: _pdfSignatory('Principal', details.principalName)),
                    pw.SizedBox(width: 6),
                    pw.Expanded(child: _pdfSignatory('Director', details.directorName)),
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

  pw.Widget _pdfSignatory(String label, String? name) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            name ?? ' ',
            style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold),
            maxLines: 1,
          ),
          pw.Divider(height: 2, thickness: 0.4),
          pw.Text(label, style: const pw.TextStyle(fontSize: 4.5)),
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
        child: Container(
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
              Padding(padding: const EdgeInsets.all(12), child: child),
            ],
          ),
        ),
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
    final theme = Theme.of(context);
    final branding = details.branding;
    final user = details.user;

    return _CardShell(
      branding: branding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (branding.hasLogo)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Image.network(
                    branding.logoUrl!,
                    height: 20,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Expanded(
                child: Text(
                  branding.schoolName ?? 'School ID',
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (details.schoolYear != null)
                Text(
                  'SY ${details.schoolYear}',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                ),
            ],
          ),
          const Divider(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                  child: user.photoUrl == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.fullName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(user.role.displayName, style: theme.textTheme.bodySmall),
                      if (details.gradeLevel != null)
                        Text(
                          '${details.gradeLevel} · ${details.section}',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                QrImageView(data: user.qrCode, size: 62, padding: EdgeInsets.zero),
              ],
            ),
          ),
          if (branding.addressLine != null)
            Text(
              branding.addressLine!,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 8),
              overflow: TextOverflow.ellipsis,
            ),
        ],
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
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 9);
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );

    return _CardShell(
      branding: details.branding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details.fullName, style: theme.textTheme.labelMedium, overflow: TextOverflow.ellipsis),
          const Divider(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: details.backRows
                  .map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 108, child: Text(row.$1, style: labelStyle)),
                          Expanded(
                            child: Text(row.$2, style: valueStyle, overflow: TextOverflow.ellipsis),
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
              Expanded(child: _Signatory(label: 'Principal', name: details.principalName)),
              const SizedBox(width: 12),
              Expanded(child: _Signatory(label: 'Director', name: details.directorName)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Signatory extends StatelessWidget {
  final String label;
  final String? name;

  const _Signatory({required this.label, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name ?? ' ',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 9, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
        const Divider(height: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 8)),
      ],
    );
  }
}
