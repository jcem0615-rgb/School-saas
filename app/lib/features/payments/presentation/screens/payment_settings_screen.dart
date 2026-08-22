import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../controllers/payment_controller.dart';

/// Where the registrar publishes the school's e-wallet QR.
///
/// Students and parents cannot pay online until this is set, so an
/// unconfigured school is called out plainly rather than left to be
/// discovered by a family hitting a dead end on the pay screen.
class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  ConsumerState<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> {
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _instructionsController = TextEditingController();
  bool _loadedOnce = false;
  bool _uploading = false;

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _uploadQr() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      // An image only: a QR has to be displayable inline on the pay screen.
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploading = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.paymentSettings,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: 'image/${file.extension}',
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    switch (result) {
      case Success<UploadedFile>(:final value):
        await ref.read(paymentActionControllerProvider.notifier).updatePaymentSettings(
              qrCodeUrl: value.url,
              qrCodeFileName: value.fileName,
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
    final settingsAsync = ref.watch(paymentSettingsProvider);

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Online Payment Setup')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load settings: $err')),
        data: (settings) {
          // Prefill once: rebinding on every rebuild would fight the user
          // as they type, since this stream re-emits on each save.
          if (!_loadedOnce) {
            _accountNameController.text = settings.accountName ?? '';
            _accountNumberController.text = settings.accountNumber ?? '';
            _instructionsController.text = settings.instructions ?? '';
            _loadedOnce = true;
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!settings.isConfigured)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Families cannot pay online until a QR or an account '
                      'number is published here.',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Payment QR', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (settings.qrCodeUrl != null)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220, maxWidth: 220),
                    child: Image.network(
                      settings.qrCodeUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Text('QR image could not be loaded.'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploading ? null : _uploadQr,
                icon: _uploading
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_2),
                label: Text(
                  _uploading
                      ? 'Uploading…'
                      : settings.qrCodeUrl == null
                          ? 'Upload payment QR'
                          : 'Replace payment QR',
                ),
              ),
              const Divider(height: 32),
              Text('Account details', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Shown next to the QR, for families transferring instead of scanning.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountNameController,
                decoration: const InputDecoration(
                    labelText: 'Account name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountNumberController,
                decoration: const InputDecoration(
                    labelText: 'Account / mobile number'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _instructionsController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Instructions for families',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () async {
                  final ok = await ref
                      .read(paymentActionControllerProvider.notifier)
                      .updatePaymentSettings(
                        accountName: _accountNameController.text,
                        accountNumber: _accountNumberController.text,
                        instructions: _instructionsController.text,
                      );
                  if (ok && context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(content: Text('Payment details saved.')));
                  }
                },
                child: const Text('Save details'),
              ),
              if (settings.updatedByName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Last updated by ${settings.updatedByName}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
