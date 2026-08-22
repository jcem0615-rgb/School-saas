import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/payment.dart';
import '../controllers/payment_controller.dart';
import '../widgets/payment_method_chip.dart';
import 'online_payment_screen.dart';
import 'receipt_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat.yMMMd();

/// Shows one student's balance, payment history, and refund history (the
/// same list, since a refund is just a row with `isRefund == true`).
/// Reused by Registrar (any student), Student (their own), and Parent
/// (a linked child's) -- the screen itself doesn't know or care which
/// role is viewing it; Firestore rules already scoped what [studentId]
/// they're even allowed to query.
class PaymentHistoryScreen extends ConsumerWidget {
  final String studentId;
  final String? studentName;
  final bool allowRefunds;

  /// Whether to offer self-service online payment.
  ///
  /// On by default because every role that can reach this screen has a
  /// legitimate reason to settle a balance: the student themself, a linked
  /// parent, and a cashier taking an e-wallet payment at the counter. The
  /// real gate is server-side -- recordPayment only lets a student pay
  /// their own record and a parent a linked child's, and restricts both to
  /// online methods -- so this flag is presentation, not security.
  final bool allowOnlinePayment;

  const PaymentHistoryScreen({
    super.key,
    required this.studentId,
    this.studentName,
    this.allowRefunds = false,
    this.allowOnlinePayment = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsAsync = ref.watch(paymentsForStudentStreamProvider(studentId));
    final balanceAsync = ref.watch(studentBalanceStreamProvider(studentId));

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(studentName ?? 'Payment History')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: balanceAsync.when(
              loading: () => const SizedBox(height: 24),
              error: (_, __) => const Text('Balance unavailable'),
              data: (balance) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Balance',
                    style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  Text(
                    _currencyFormat.format(balance),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (balance < 0)
                    Text(
                      'Credit balance',
                      style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  // Nothing owed means nothing to pay -- offering the button
                  // on a settled or credit balance would only invite an
                  // overpayment the refund flow then has to undo.
                  if (allowOnlinePayment && balance > 0) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OnlinePaymentScreen(
                            studentId: studentId,
                            // The submission records who the money is for,
                            // so a reviewer sees a name rather than an id.
                            studentName: studentName ?? 'This student',
                            outstandingBalance: balance,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Pay online'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: paymentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load payments: $err')),
              data: (payments) {
                if (payments.isEmpty) {
                  return const Center(child: Text('No payment history yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _PaymentTile(
                    payment: payments[index],
                    studentId: studentId,
                    allowRefunds: allowRefunds,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends ConsumerWidget {
  final Payment payment;
  final String studentId;
  final bool allowRefunds;

  const _PaymentTile({required this.payment, required this.studentId, required this.allowRefunds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRefund = allowRefunds && !payment.isRefund && payment.status == PaymentStatus.completed;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(studentId: studentId, receiptNumber: payment.receiptNumber),
          ),
        ),
        leading: Icon(
          payment.isRefund ? Icons.replay_circle_filled_outlined : Icons.receipt_long_outlined,
          color: payment.isRefund ? Colors.orange : null,
        ),
        title: Text(
          _currencyFormat.format(payment.amount.abs()),
          style: TextStyle(fontWeight: FontWeight.w600, color: payment.isRefund ? Colors.orange : null),
        ),
        subtitle: Text('${payment.purpose.displayLabel} · ${_dateFormat.format(payment.createdAt)}'),
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PaymentMethodChip(method: payment.method),
            if (canRefund)
              IconButton(
                icon: const Icon(Icons.undo, size: 20),
                tooltip: 'Refund',
                onPressed: () => _showRefundDialog(context, ref),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRefundDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refund this payment?'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(labelText: 'Reason'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(paymentActionControllerProvider.notifier).recordRefund(
            paymentId: payment.id,
            reason: reasonController.text,
          );
    }
  }
}
