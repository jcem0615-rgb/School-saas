import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../registrar_portal/domain/entities/student_summary.dart';
import '../../../registrar_portal/presentation/controllers/registrar_controller.dart';
import '../../domain/entities/payment.dart';
import '../../domain/entities/receipt_booklet.dart';
import '../../domain/entities/receipt_series.dart';
import '../controllers/payment_controller.dart';
import 'receipt_screen.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// Accepts [studentId] and [studentName] as navigation params, from the
/// Registrar's Student Records screen. Opened from the dashboard instead,
/// the id is typed -- and then it has to be resolved against the roster
/// before anything is recorded.
///
/// Typed entry accepts either the record's id or the student number
/// printed on the ID card, because the number is what a cashier reads off
/// the card in front of them. It used to accept neither in the sense that
/// mattered: any string was taken, a receipt was issued, and nobody's
/// balance moved. A payment that cannot name the student it is for is not
/// a payment, so this screen will not send one.
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

  /// The number pre-printed on the OR the cashier is about to hand over.
  /// Pre-filled with what the series says comes next, and editable --
  /// booklets get used out of order and the paper is the truth.
  final _receiptController = TextEditingController();
  bool _receiptSeeded = false;
  PaymentMethod _method = PaymentMethod.cash;
  PaymentPurpose _purpose = PaymentPurpose.tuition;

  /// What is typed, held in state so the resolved student re-renders on
  /// every keystroke rather than only when something else rebuilds.
  String _typedId = '';

  @override
  void initState() {
    super.initState();
    _studentIdController = TextEditingController(text: widget.studentId ?? '');
    _typedId = _studentIdController.text;
  }

  /// The roster row this payment is for, or null while the id matches
  /// nothing. Matched on the record id or the printed student number.
  StudentSummary? _resolve(List<StudentSummary> roster) {
    final query = _typedId.trim().toLowerCase();
    if (query.isEmpty) return null;
    for (final s in roster) {
      if (s.id.toLowerCase() == query ||
          s.studentNumber.toLowerCase() == query) {
        return s;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _amountController.dispose();
    _referenceController.dispose();
    _receiptController.dispose();
    super.dispose();
  }

  /// The OR field, and the running hint of what number is expected.
  ///
  /// Seeded rather than forced: the expected number is a very good guess
  /// and occasionally wrong -- a booklet used out of order, a receipt
  /// spoiled and skipped -- and the number on the paper the family is
  /// holding wins over the number the system predicted.
  List<Widget>? _officialReceiptField() {
    final booklets = ref.watch(receiptBookletsProvider).valueOrNull ?? const [];
    final active = booklets.where((b) => b.isActive).toList();
    if (active.length != 1) return null;
    final booklet = active.single;

    final payments = ref.watch(allPaymentsForSeriesProvider).valueOrNull ?? const [];
    final series = reconcileSeries(booklet: booklet, payments: payments);
    final expected = series.nextExpected;

    if (!_receiptSeeded && expected != null) {
      _receiptSeeded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _receiptController.text.isEmpty) {
          _receiptController.text = booklet.format(expected);
        }
      });
    }

    return [
      const SizedBox(height: 12),
      TextField(
        controller: _receiptController,
        decoration: InputDecoration(
          labelText: 'Official receipt no.',
          helperText: expected == null
              ? 'This booklet is full. Register the next one.'
              : 'Booklet ${booklet.rangeLabel}. Next expected '
                  '${booklet.format(expected)}.',
        ),
      ),
    ];
  }

  bool get _referenceRequired =>
      _method == PaymentMethod.gcash || _method == PaymentMethod.bankTransfer;

  Future<void> _submit(StudentSummary student) async {
    final amount = double.tryParse(_amountController.text) ?? -1;

    // The record's id, never what was typed: a cashier who entered the
    // student number would otherwise send a value nothing matches.
    final outcome = await ref.read(paymentActionControllerProvider.notifier).recordPayment(
          studentId: student.id,
          amount: amount,
          method: _method,
          purpose: _purpose,
          referenceNumber: _referenceController.text,
          officialReceiptNo: ReceiptBooklet.parseNumber(_receiptController.text),
        );

    if (outcome != null && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            studentId: student.id,
            receiptNumber: outcome.receiptNumber,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(paymentActionControllerProvider);
    // The whole roster, watched rather than read: the balance shown below
    // is the one from this stream, so it moves the moment the payment
    // lands instead of waiting for the screen to be reopened.
    final rosterAsync = ref.watch(studentsStreamProvider);
    final roster = rosterAsync.valueOrNull ?? const <StudentSummary>[];
    final student = _resolve(roster);

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
              TextField(
                controller: _studentIdController,
                enabled: widget.studentId == null,
                onChanged: (v) => setState(() => _typedId = v),
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  helperText: 'The record ID or the number on the ID card.',
                ),
              ),
              const SizedBox(height: 12),
              _StudentBanner(
                student: student,
                typed: _typedId.trim(),
                loading: rosterAsync.isLoading,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount (₱)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentPurpose>(
                isExpanded: true,
                value: _purpose,
                decoration: const InputDecoration(labelText: 'Purpose'),
                items: PaymentPurpose.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.displayLabel)))
                    .toList(),
                onChanged: (v) => setState(() => _purpose = v ?? _purpose),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<PaymentMethod>(
                isExpanded: true,
                value: _method,
                decoration: const InputDecoration(labelText: 'Payment Method'),
                items: PaymentMethod.values
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.displayLabel)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v ?? _method),
              ),
              if (_referenceRequired) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _referenceController,
                  decoration: const InputDecoration(labelText: 'Reference Number'),
                ),
              ],
              // Only when the school has registered a booklet. A school
              // not issuing official receipts must not be shown a field
              // it has no answer for.
              ...?_officialReceiptField(),
              const SizedBox(height: 24),
              FilledButton(
                // Disabled until the id names somebody. Recording a
                // payment against nobody is the failure this screen
                // exists to prevent, and a disabled button says so
                // earlier than an error would.
                onPressed: actionState.isLoading || student == null
                    ? null
                    : () => _submit(student),
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

/// Who the money is being taken from, and what they owe right now.
///
/// The balance is the point of this: a cashier keying an id has no other
/// confirmation that they reached the right record, and after the payment
/// it is the figure that proves the deduction happened.
class _StudentBanner extends StatelessWidget {
  final StudentSummary? student;
  final String typed;
  final bool loading;

  const _StudentBanner({
    required this.student,
    required this.typed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (student == null) {
      final waiting = typed.isEmpty || loading;
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: waiting
              ? scheme.surfaceContainerHighest
              : scheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              waiting ? Icons.badge_outlined : Icons.person_off_outlined,
              size: 20,
              color: waiting ? scheme.onSurfaceVariant : scheme.onErrorContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                waiting
                    ? 'Enter the student ID to see who this payment is for.'
                    : 'No student has that ID. Nothing will be recorded.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      waiting ? scheme.onSurfaceVariant : scheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final s = student!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.fullName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
            ),
          ),
          Text(
            '${s.studentNumber} - ${s.classLabel}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            'Current balance: ${_currencyFormat.format(s.balance)}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
