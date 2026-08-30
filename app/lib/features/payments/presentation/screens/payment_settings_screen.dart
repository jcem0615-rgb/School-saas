import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../domain/entities/bank_account.dart';
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

  Future<void> _saveAccounts(List<BankAccount> accounts) async {
    final ok = await ref
        .read(paymentActionControllerProvider.notifier)
        .updatePaymentSettings(bankAccounts: accounts);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(ok ? 'Bank accounts saved.' : 'That could not be saved.'),
      ));
  }

  /// Adds a new account, or edits one in place.
  ///
  /// The whole list is written back rather than the one row, because the
  /// list is one field on one document -- there is no per-row write, and
  /// merging a partial list would drop whatever the editor did not touch.
  Future<void> _editAccount(List<BankAccount> existing, BankAccount? account) async {
    final edited = await showModalBottomSheet<BankAccount>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BankAccountSheet(account: account),
    );
    if (edited == null) return;
    await _saveAccounts([
      if (account == null) ...existing,
      if (account == null)
        edited
      else
        for (final other in existing)
          if (other.id == account.id) edited else other,
    ]);
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
              const Divider(height: 32),
              Text('Bank accounts', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Offered to families who choose Bank Transfer. Which account '
                'they sent it to is recorded on the submission, so the '
                'cashier knows which statement to check.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (settings.bankAccounts.isEmpty)
                Text(
                  'None yet. Without one, Bank Transfer is not offered as a '
                  'way to pay.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                )
              else
                for (final account in settings.bankAccounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      account.isActive
                          ? Icons.account_balance_outlined
                          : Icons.do_not_disturb_on_outlined,
                      color: account.isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    title: Text(account.label),
                    subtitle: Text(
                      '${account.accountName}\n${account.accountNumber}'
                      '${account.isActive ? '' : '  ·  closed'}',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => _editAccount(settings.bankAccounts, account),
                        ),
                        IconButton(
                          icon: Icon(account.isActive
                              ? Icons.toggle_on_outlined
                              : Icons.toggle_off_outlined),
                          tooltip: account.isActive ? 'Stop offering this' : 'Offer again',
                          // Closed rather than deleted: submissions point
                          // at it, and a row that vanishes takes their
                          // meaning with it.
                          onPressed: () => _saveAccounts([
                            for (final other in settings.bankAccounts)
                              if (other.id == account.id)
                                other.copyWith(isActive: !other.isActive)
                              else
                                other,
                          ]),
                        ),
                      ],
                    ),
                  ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _editAccount(settings.bankAccounts, null),
                  icon: const Icon(Icons.add),
                  label: const Text('Add bank account'),
                ),
              ),
              const Divider(height: 32),
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

/// Add or edit one bank account.
class _BankAccountSheet extends StatefulWidget {
  final BankAccount? account;
  const _BankAccountSheet({this.account});

  @override
  State<_BankAccountSheet> createState() => _BankAccountSheetState();
}

class _BankAccountSheetState extends State<_BankAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _bank = TextEditingController(text: widget.account?.bankName ?? '');
  late final _name = TextEditingController(text: widget.account?.accountName ?? '');
  late final _number = TextEditingController(text: widget.account?.accountNumber ?? '');
  late final _branch = TextEditingController(text: widget.account?.branch ?? '');

  @override
  void dispose() {
    _bank.dispose();
    _name.dispose();
    _number.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      BankAccount(
        // Kept across an edit, so a submission that recorded this
        // account still points at the same one after a typo is fixed.
        id: widget.account?.id ??
            'ba_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        bankName: _bank.text.trim(),
        accountName: _name.text.trim(),
        accountNumber: _number.text.trim(),
        branch: _branch.text.trim().isEmpty ? null : _branch.text.trim(),
        isActive: widget.account?.isActive ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.account == null ? 'Add bank account' : 'Edit bank account',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bank,
              decoration: const InputDecoration(
                labelText: 'Bank',
                hintText: 'BPI, BDO, LandBank',
              ),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Which bank?'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Account name'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => (value == null || value.trim().isEmpty)
                  // A family checking their transfer landed in the right
                  // place reads this before they read the number.
                  ? 'Whose account is it?'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _number,
              decoration: const InputDecoration(labelText: 'Account number'),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Money sent to an account with no number goes nowhere.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _branch,
              decoration: const InputDecoration(
                labelText: 'Branch (optional)',
                hintText: 'Only if the school banks at more than one',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Save account'),
            ),
          ],
        ),
      ),
    );
  }
}
