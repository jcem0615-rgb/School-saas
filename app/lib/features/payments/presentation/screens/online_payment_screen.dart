import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../domain/entities/payment.dart';
import '../controllers/payment_controller.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Where a student or parent declares an online payment.
///
/// The important thing this screen does NOT do is credit the balance. The
/// family pays the school's e-wallet outside the app, then comes here to
/// say so: reference number, receipt image, amount. A registrar checks
/// that against the school's account and approves, and only then does the
/// balance move.
///
/// That ordering is the whole point. Anything that credited an account on
/// the payer's say-so would let anyone clear their own fees by typing a
/// plausible reference number.
class OnlinePaymentScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String studentName;
  final double outstandingBalance;

  const OnlinePaymentScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.outstandingBalance,
  });

  @override
  ConsumerState<OnlinePaymentScreen> createState() => _OnlinePaymentScreenState();
}

class _OnlinePaymentScreenState extends ConsumerState<OnlinePaymentScreen> {
  late final TextEditingController _amountController = TextEditingController(
    text: widget.outstandingBalance > 0 ? widget.outstandingBalance.toStringAsFixed(2) : '',
  );
  final _referenceController = TextEditingController();
  PaymentPurpose _purpose = PaymentPurpose.tuition;
  PaymentMethod _method = PaymentMethod.gcash;

  String? _receiptUrl;
  String? _receiptFileName;
  bool _uploading = false;
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      // Matches storage.rules, which accepts images and PDFs only.
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploading = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.paymentReceipts,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType:
              file.extension == 'pdf' ? 'application/pdf' : 'image/${file.extension}',
        );
    if (!mounted) return;
    setState(() => _uploading = false);

    switch (result) {
      case Success<UploadedFile>(:final value):
        setState(() {
          _receiptUrl = value.url;
          _receiptFileName = value.fileName;
        });
      case Error<UploadedFile>(:final failure):
        _snack(failure.message);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text) ?? -1;
    if (amount <= 0) {
      _snack('Enter an amount greater than zero.');
      return;
    }
    if (_referenceController.text.trim().isEmpty) {
      _snack('Enter the transaction reference number from your receipt.');
      return;
    }
    if (_receiptUrl == null) {
      _snack('Attach a photo or screenshot of your receipt.');
      return;
    }

    setState(() => _submitting = true);
    final ok = await ref.read(paymentActionControllerProvider.notifier).submitOnlinePayment(
          studentId: widget.studentId,
          studentName: widget.studentName,
          amount: amount,
          method: _method,
          purpose: _purpose,
          referenceNumber: _referenceController.text,
          receiptUrl: _receiptUrl,
          receiptFileName: _receiptFileName,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!ok) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.hourglass_top_outlined),
        title: const Text('Sent for review'),
        content: const Text(
          'The cashier will check this against the school account. Your '
          'balance updates once it is approved — you can follow it under '
          'Payments & Balance.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(paymentSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Pay Online')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1 -- where to send the money.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Send your payment', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (settings == null)
                      const Center(child: CircularProgressIndicator())
                    else if (!settings.isConfigured)
                      Text(
                        'The school has not published payment details yet. '
                        'Please contact the registrar before paying.',
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    else ...[
                      if (settings.qrCodeUrl != null)
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 240),
                            child: Image.network(
                              settings.qrCodeUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Text('QR image could not be loaded.'),
                            ),
                          ),
                        ),
                      if (settings.accountName != null || settings.accountNumber != null) ...[
                        const SizedBox(height: 12),
                        if (settings.accountName != null)
                          Text('Account: ${settings.accountName}'),
                        if (settings.accountNumber != null)
                          SelectableText('Number: ${settings.accountNumber}'),
                      ],
                      if (settings.instructions?.trim().isNotEmpty ?? false) ...[
                        const SizedBox(height: 12),
                        Text(settings.instructions!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Step 2 -- prove it.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('2. Tell us about it', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Paying for ${widget.studentName} · outstanding '
                      '${_currencyFormat.format(widget.outstandingBalance)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Transaction reference number',
                        hintText: 'From your e-wallet receipt',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Amount sent (₱)',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentMethod>(
                      isExpanded: true,
                      value: _method,
                      decoration: const InputDecoration(
                          labelText: 'Paid via'),
                      // Only the online methods: cash and bank transfer are
                      // things a cashier attests to, not a family.
                      items: const [PaymentMethod.gcash, PaymentMethod.online]
                          .map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel)))
                          .toList(),
                      onChanged: (v) => setState(() => _method = v ?? _method),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<PaymentPurpose>(
                      isExpanded: true,
                      value: _purpose,
                      decoration: const InputDecoration(
                          labelText: 'Purpose'),
                      items: PaymentPurpose.values
                          .map((p) => DropdownMenuItem(value: p, child: Text(p.displayLabel)))
                          .toList(),
                      onChanged: (v) => setState(() => _purpose = v ?? _purpose),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _pickReceipt,
                      icon: _uploading
                          ? const SizedBox(
                              height: 16, width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.receipt_long_outlined),
                      label: Text(_uploading ? 'Uploading…' : 'Attach receipt'),
                    ),
                    if (_receiptFileName != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(_receiptFileName!, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _receiptUrl = null;
                            _receiptFileName = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(_submitting ? 'Sending…' : 'Submit for review'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 8),
            Text(
              'Your balance changes only after the cashier verifies this '
              'payment against the school account.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
