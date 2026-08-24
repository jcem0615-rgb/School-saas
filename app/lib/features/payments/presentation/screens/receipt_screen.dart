import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../controllers/payment_controller.dart';
import '../widgets/payment_method_chip.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateTimeFormat = DateFormat.yMMMd().add_jm();

/// Shows one receipt, found by matching [receiptNumber] within the
/// student's payment stream (already loaded for the history screen, so
/// this avoids a second round-trip query for the common "just recorded a
/// payment, now show the receipt" flow). PDF export/printing is wired up
/// in the Documents module, which reuses this same [Payment] entity.
class ReceiptScreen extends ConsumerWidget {
  final String studentId;
  final String receiptNumber;

  const ReceiptScreen({super.key, required this.studentId, required this.receiptNumber});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(paymentsForStudentStreamProvider(studentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined),
            tooltip: 'Print / Export (available in Documents module)',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PDF export is available once the Documents module is enabled.')),
            ),
          ),
        ],
      ),
      body: paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load receipt: $err')),
        data: (payments) {
          final matches = payments.where((p) => p.receiptNumber == receiptNumber);
          if (matches.isEmpty) {
            return const Center(child: Text('Receipt not found.'));
          }
          final payment = matches.first;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          payment.isRefund ? Icons.replay_circle_filled_outlined : Icons.check_circle_outline,
                          size: 48,
                          color: payment.isRefund ? Colors.orange : Colors.green,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            _currencyFormat.format(payment.amount.abs()),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        Center(
                          child: Text(
                            payment.isRefund ? 'REFUND' : 'PAYMENT RECEIVED',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const Divider(height: 32),
                        _ReceiptRow(label: 'Receipt No.', value: payment.receiptNumber),
                        _ReceiptRow(label: 'Date', value: _dateTimeFormat.format(payment.createdAt)),
                        _ReceiptRow(label: 'Purpose', value: payment.purpose.displayLabel),
                        const SizedBox(height: 4),
                        PaymentMethodChip(method: payment.method),
                        if (payment.referenceNumber != null)
                          _ReceiptRow(label: 'Reference No.', value: payment.referenceNumber!),
                        _ReceiptRow(label: 'Collected By', value: payment.collectedByName),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
