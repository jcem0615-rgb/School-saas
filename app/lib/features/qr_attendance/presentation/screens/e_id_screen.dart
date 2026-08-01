import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';

/// CR80 -- the standard ID-card size, 85.6mm x 54mm.
///
/// Laying the card out at true physical size matters: printed to an ID
/// card printer it comes out correct, and printed to an ordinary printer
/// it comes out at the same size on A4, so it can be cut out and it still
/// fits a lanyard holder.
const _cardWidthMm = 85.6;
const _cardHeightMm = 54.0;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('My School ID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: () => _print(user, branding),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(child: _IdCard(user: user, branding: branding)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _print(user, branding),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print ID'),
          ),
          const SizedBox(height: 8),
          Text(
            'Prints at true card size (85.6 × 54 mm). Send it to an ID card '
            'printer directly, or print on paper and cut along the border.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
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

  Future<void> _print(AppUser user, SchoolBranding branding) async {
    await Printing.layoutPdf(
      onLayout: (format) => _buildPdf(user, branding),
    );
  }

  /// Builds the card as a PDF at exactly card size.
  ///
  /// The QR is regenerated here rather than screenshotting the widget, so
  /// it prints as crisp vectors at any scale -- a rasterised QR at 54mm is
  /// unreliable to scan.
  Future<Uint8List> _buildPdf(AppUser user, SchoolBranding branding) async {
    final doc = pw.Document();

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

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Stack(
          children: [
            if (logo != null)
              pw.Positioned.fill(
                child: pw.Center(
                  // Watermark: visible enough to identify the school,
                  // faint enough not to fight the text over it.
                  child: pw.Opacity(opacity: 0.08, child: pw.Image(logo, height: 40 * PdfPageFormat.mm)),
                ),
              ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
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
                  ],
                ),
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
                              user.fullName,
                              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                            ),
                            pw.SizedBox(height: 1),
                            pw.Text(user.role.displayName, style: const pw.TextStyle(fontSize: 7)),
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

    return doc.save();
  }
}

/// On-screen preview, laid out to the same proportions as the printed card
/// so what you see is what comes out of the printer.
class _IdCard extends StatelessWidget {
  final AppUser user;
  final SchoolBranding branding;

  const _IdCard({required this.user, required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AspectRatio(
      aspectRatio: _cardWidthMm / _cardHeightMm,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
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
              padding: const EdgeInsets.all(12),
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
                    ],
                  ),
                  const Divider(height: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundImage:
                              user.photoUrl != null ? NetworkImage(user.photoUrl!) : null,
                          child: user.photoUrl == null ? const Icon(Icons.person) : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.fullName,
                                style: theme.textTheme.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(user.role.displayName, style: theme.textTheme.bodySmall),
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
                        QrImageView(
                          data: user.qrCode,
                          size: 62,
                          padding: EdgeInsets.zero,
                        ),
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
            ),
          ],
        ),
      ),
    );
  }
}
