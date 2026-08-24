import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../controllers/admin_controller.dart';

/// Where the admin sets the school's logo and name.
///
/// The logo is not decoration: it appears behind the app shell and on every
/// printed e-ID, so an unbranded school produces plain, generic ID cards.
class BrandingScreen extends ConsumerStatefulWidget {
  const BrandingScreen({super.key});

  @override
  ConsumerState<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends ConsumerState<BrandingScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _principalController = TextEditingController();
  final _directorController = TextEditingController();
  final _schoolYearController = TextEditingController();
  bool _loadedOnce = false;
  bool _uploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _principalController.dispose();
    _directorController.dispose();
    _schoolYearController.dispose();
    super.dispose();
  }

  /// Picks an image, uploads it, and hands the resulting URL to [save].
  ///
  /// Shared by the logo and both signatures because the awkward parts are
  /// identical -- and because the ordering matters the same way each
  /// time: the bytes go to Storage first, and only a successful upload
  /// gets written to the branding document. Saving the URL first would
  /// point every printed ID at a file that does not exist.
  Future<void> _pickAndUpload({
    required UploadFolder folder,
    required Future<void> Function(UploadedFile file) save,
  }) async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploading = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: folder,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: 'image/${file.extension}',
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    switch (result) {
      case Success<UploadedFile>(:final value):
        await save(value);
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Saved. New ID cards will use it.')));
        }
      case Error<UploadedFile>(:final failure):
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(failure.message)));
        }
    }
  }

  Future<void> _uploadLogo() => _pickAndUpload(
        folder: UploadFolder.branding,
        save: (file) => ref.read(adminActionControllerProvider.notifier).updateBranding(
              logoUrl: file.url,
              logoFileName: file.fileName,
            ),
      );

  Future<void> _uploadSignature({required bool principal}) => _pickAndUpload(
        folder: UploadFolder.signatures,
        save: (file) => ref.read(adminActionControllerProvider.notifier).updateBranding(
              principalSignatureUrl: principal ? file.url : null,
              directorSignatureUrl: principal ? null : file.url,
            ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandingAsync = ref.watch(brandingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('School Branding')),
      body: brandingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load branding: $err')),
        data: (branding) {
          // Prefill once -- this stream re-emits on every save, and
          // rebinding each time would fight the user as they type.
          if (!_loadedOnce) {
            _nameController.text = branding.schoolName ?? '';
            _addressController.text = branding.addressLine ?? '';
            _principalController.text = branding.principalName ?? '';
            _directorController.text = branding.directorName ?? '';
            _schoolYearController.text = branding.schoolYear ?? '';
            _loadedOnce = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Logo', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Shown behind the app and on every printed ID card.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (branding.hasLogo)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: Image.network(
                      branding.logoUrl!,
                      errorBuilder: (_, __, ___) => const Text('Logo could not be loaded.'),
                    ),
                  ),
                )
              else
                Text('No logo uploaded yet.', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _uploadLogo,
                icon: _uploading
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined),
                label: Text(
                  _uploading
                      ? 'Uploading…'
                      : branding.hasLogo
                          ? 'Replace logo'
                          : 'Upload logo',
                ),
              ),
              const Divider(height: 32),
              Text('School details', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'School name (as printed)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                    labelText: 'Address line'),
              ),
              const Divider(height: 32),
              Text('Printed on every ID', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'The school year and the two signatories appear on the back '
                'of every student and employee ID card. Set them here once '
                'rather than per person.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schoolYearController,
                decoration: const InputDecoration(
                    labelText: 'School year (e.g. 2026-2027)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _principalController,
                decoration: const InputDecoration(
                    labelText: 'Principal name'),
              ),
              const SizedBox(height: 12),
              _SignatureField(
                label: 'Principal signature',
                url: branding.principalSignatureUrl,
                busy: _uploading,
                onUpload: () => _uploadSignature(principal: true),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _directorController,
                decoration: const InputDecoration(
                    labelText: 'Director name'),
              ),
              const SizedBox(height: 12),
              _SignatureField(
                label: 'Director signature',
                url: branding.directorSignatureUrl,
                busy: _uploading,
                onUpload: () => _uploadSignature(principal: false),
              ),
              const SizedBox(height: 8),
              Text(
                'A signature uploaded here is printed above that name on '
                'every ID card the school issues, students and employees '
                'alike — nobody signs cards one at a time. A scan on white '
                'paper, or a PNG with a transparent background, prints '
                'best. Leave it empty and the card prints a blank line to '
                'sign by hand.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final ok = await ref.read(adminActionControllerProvider.notifier).updateBranding(
                        schoolName: _nameController.text,
                        addressLine: _addressController.text,
                        principalName: _principalController.text,
                        directorName: _directorController.text,
                        schoolYear: _schoolYearController.text,
                      );
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Branding saved.')));
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A signature: what is on file, and the button to change it.
class _SignatureField extends StatelessWidget {
  final String label;
  final String? url;
  final bool busy;
  final VoidCallback onUpload;

  const _SignatureField({
    required this.label,
    required this.url,
    required this.busy,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = url != null && url!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 48,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
            // White behind it whatever the app theme is: a scanned
            // signature is black ink on paper, and in dark mode on a dark
            // panel it is invisible.
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(4),
          child: has
              ? Image.network(
                  url!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Center(child: Icon(Icons.broken_image_outlined, size: 18)),
                )
              : Center(
                  child: Text(
                    'None',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: busy ? null : onUpload,
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: Text(has ? 'Replace' : 'Upload'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
