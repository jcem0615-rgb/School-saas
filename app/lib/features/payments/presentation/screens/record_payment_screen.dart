import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/payment.dart';
import '../controllers/payment_controller.dart';
import 'receipt_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Accepts [studentId] and [studentName] as navigation params -- in the
/// full app these come from the Registrar's Student Records screen (that
/// module comes later in the build). Until then, this screen also accepts
/// manual entry of a student ID so it's independently testable/usable.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  final String? studentId;
  final String? studentName;

  const RecordPaymentScreen({super.key, this.studentId, this.studentName});

  @override
  ConsumerState<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  late final TextEditingController _studentIdController;
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  PaymentPurpose _purpose = PaymentPurpose.tuition;

  @override
  void initState() {
    super.initState();
    _studentIdController = TextEditingController(text: widget.studentId ?? '');
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  bool get _referenceRequired =>
      _method == PaymentMethod.gcash || _method == PaymentMethod.bankTransfer;

  Future<void> _submit() async {
    final studentId = _studentIdController.text.trim();
    final amount = double.tryParse(_amountController.text) ?? -1;

    final receiptNumber = await ref.read(paymentActionControllerProvider.notifier).recordPayment(
          studentId: studentId,
          amount: amount,
          method: _method,
          purpose: _purpose,
          referenceNumber: _referenceController.text,
        );

    if (receiptNumber != null && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(studentId: studentId, receiptNumber: receiptNumber),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(paymentActionControllerProvider);
    final balanceAsync = widget.studentId != null
        ? ref.watch(studentBalanceStreamProvider(widget.studentId!))
        : null;

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Record Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.studentName != null) ...[
                Text(widget.studentName!, style: Theme.of(context).textTheme.titleLarge),
                if (balanceAsync != null)
                  balanceAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (balance) => Text(
                      'Current balance: ${_currencyFormat.format(balance)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _studentIdController,
                enabled: widget.studentId == null,
                decoration: const InputDecoration(labelText: 'Student ID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (₱)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentPurpose>(
                initialValue: _purpose,
                decoration: const InputDecoration(labelText: 'Purpose', border: OutlineInputBorder()),
                items: PaymentPurpose.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.displayLabel)))
                    .toList(),
                onChanged: (v) => setState(() => _purpose = v ?? _purpose),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                initialValue: _method,
                decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
                items: PaymentMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              if (_referenceRequired) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _referenceController,
                  decoration: const InputDecoration(labelText: 'Reference Number', border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: actionState.isLoading ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: actionState.isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Record Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
