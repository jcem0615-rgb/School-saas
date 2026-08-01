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
  bool _loadedOnce = false;
  bool _uploading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _uploadLogo() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploading = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.branding,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: 'image/${file.extension}',
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    switch (result) {
      case Success<UploadedFile>(:final value):
        await ref.read(adminActionControllerProvider.notifier).updateBranding(
              logoUrl: value.url,
              logoFileName: value.fileName,
            );
      case Error<UploadedFile>(:final failure):
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(failure.message)));
        }
    }
  }

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
                    labelText: 'School name (as printed)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                    labelText: 'Address line', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final ok = await ref.read(adminActionControllerProvider.notifier).updateBranding(
                        schoolName: _nameController.text,
                        addressLine: _addressController.text,
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
