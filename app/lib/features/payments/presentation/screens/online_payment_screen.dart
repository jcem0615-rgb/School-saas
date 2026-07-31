import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/payment.dart';
import '../controllers/payment_controller.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Simulated e-wallet checkout.
///
/// **No real GCash integration.** There is no merchant account, no API
/// call, and no money movement -- confirming here goes straight to the
/// same `recordPayment` path a cashier uses, with `method: gcash` and a
/// generated reference number. That is deliberate for testing: the point
/// is to exercise the balance/receipt/audit flow end to end without
/// wiring a payment provider.
///
/// When a real gateway is added, only [_confirm] should change: it would
/// hand off to the provider, and record the payment on the provider's
/// webhook rather than on the user tapping a button. Everything
/// downstream -- balance recalculation, receipt numbering, audit trail --
/// already works and would not need touching.
class OnlinePaymentScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String? studentName;
  final double outstandingBalance;

  const OnlinePaymentScreen({
    super.key,
    required this.studentId,
    required this.outstandingBalance,
    this.studentName,
  });

  @override
  ConsumerState<OnlinePaymentScreen> createState() => _OnlinePaymentScreenState();
}

class _OnlinePaymentScreenState extends ConsumerState<OnlinePaymentScreen> {
  late final TextEditingController _amountController =
      TextEditingController(text: widget.outstandingBalance > 0 ? widget.outstandingBalance.toStringAsFixed(2) : '');
  final _mobileController = TextEditingController();
  PaymentPurpose _purpose = PaymentPurpose.tuition;
  bool _processing = false;

  @override
  void dispose() {
    _amountController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final amount = double.tryParse(_amountController.text) ?? -1;
    if (amount <= 0) {
      _snack('Enter an amount greater than zero.');
      return;
    }
    if (amount > widget.outstandingBalance) {
      _snack('Amount is more than the outstanding balance.');
      return;
    }

    setState(() => _processing = true);
    // Stand-in for the round trip to a payment provider, so the pending
    // state is visible rather than instantaneous.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    // A real gateway supplies this; here it is generated so the payment
    // still carries a traceable reference through to the receipt.
    final reference = 'GC-${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';

    final outcome = await ref.read(paymentActionControllerProvider.notifier).recordPayment(
          studentId: widget.studentId,
          amount: amount,
          method: PaymentMethod.gcash,
          purpose: _purpose,
          referenceNumber: reference,
        );

    if (!mounted) return;
    setState(() => _processing = false);

    if (outcome == null) return; // controller surfaced the failure already
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline),
        title: const Text('Payment received'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receipt ${outcome.receiptNumber}'),
            const SizedBox(height: 4),
            Text('Reference $reference'),
            const SizedBox(height: 12),
            Text('Remaining balance: ${_currencyFormat.format(outcome.newBalance)}'),
          ],
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

    return Scaffold(
      appBar: AppBar(title: const Text('Pay Online')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: theme.colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.onTertiaryContainer),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Test mode — this is not connected to GCash. Confirming records '
                        'a real payment against the balance so the flow can be tested, '
                        'but no money moves.',
                        style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (widget.studentName != null) ...[
              Text('Paying for', style: theme.textTheme.labelMedium),
              Text(widget.studentName!, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
            ],
            Text('Outstanding balance', style: theme.textTheme.labelMedium),
            Text(
              _currencyFormat.format(widget.outstandingBalance),
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _mobileController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'GCash mobile number',
                hintText: '09XX XXX XXXX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_iphone),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount to pay (₱)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PaymentPurpose>(
              isExpanded: true,
              value: _purpose,
              decoration: const InputDecoration(labelText: 'Purpose', border: OutlineInputBorder()),
              items: PaymentPurpose.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.displayLabel)))
                  .toList(),
              onChanged: (v) => setState(() => _purpose = v ?? _purpose),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _processing ? null : _confirm,
              icon: _processing
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline),
              label: Text(_processing ? 'Processing…' : 'Confirm payment'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
