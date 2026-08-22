import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/entities/payment_submission.dart';
import '../controllers/payment_controller.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat.yMMMd().add_jm();

/// The cashier's queue of online payments awaiting verification.
///
/// Approving here is what actually credits a student -- until then the
/// submission is only a claim. The screen therefore surfaces the two
/// things a reviewer needs to check before deciding: the reference number
/// (against the school's e-wallet) and the receipt image.
class PaymentReviewScreen extends ConsumerStatefulWidget {
  const PaymentReviewScreen({super.key});

  @override
  ConsumerState<PaymentReviewScreen> createState() => _PaymentReviewScreenState();
}

class _PaymentReviewScreenState extends ConsumerState<PaymentReviewScreen> {
  bool _pendingOnly = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = _pendingOnly
        ? ref.watch(pendingSubmissionsProvider)
        : ref.watch(allSubmissionsProvider);

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Online Payments')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Awaiting review')),
                ButtonSegment(value: false, label: Text('All')),
              ],
              selected: {_pendingOnly},
              onSelectionChanged: (v) => setState(() => _pendingOnly = v.first),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load submissions: $err')),
              data: (submissions) {
                if (submissions.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _pendingOnly
                            ? 'Nothing awaiting review.'
                            : 'No online payments have been submitted yet.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: submissions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _SubmissionCard(
                    submission: submissions[i],
                    onDecide: (approve) => _decide(submissions[i], approve),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );
  }

  Future<void> _decide(PaymentSubmission s, bool approve) async {
    final remarksController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve payment?' : 'Reject payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              approve
                  ? 'This records a ${_currencyFormat.format(s.amount)} payment for '
                      '${s.studentName} and reduces their balance.'
                  : 'No payment is recorded and the balance is unchanged. '
                      'Tell the family what was wrong so they can correct it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              decoration: InputDecoration(
                labelText: approve ? 'Note (optional)' : 'Reason',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(paymentActionControllerProvider.notifier).decideSubmission(
          submissionId: s.id,
          approve: approve,
          remarks: remarksController.text,
        );
  }
}

class _SubmissionCard extends StatelessWidget {
  final PaymentSubmission submission;
  final void Function(bool approve) onDecide;

  const _SubmissionCard({required this.submission, required this.onDecide});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = submission;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.studentName, style: theme.textTheme.titleMedium),
                ),
                Text(_currencyFormat.format(s.amount), style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${s.purpose.displayLabel} · ${s.method.displayLabel} · '
              'filed by ${s.submittedByName} (${s.submittedByRole})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            // The reference is what a cashier matches against the school's
            // e-wallet, so it is selectable rather than merely displayed.
            Row(
              children: [
                const Icon(Icons.confirmation_number_outlined, size: 16),
                const SizedBox(width: 6),
                Expanded(child: SelectableText(s.referenceNumber)),
              ],
            ),
            Text(_dateFormat.format(s.submittedAt), style: theme.textTheme.bodySmall),
            if (s.receiptUrl != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(s.receiptUrl!);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open the receipt.')),
                    );
                  }
                },
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(s.receiptFileName ?? 'View receipt'),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No receipt attached.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            if (s.isPending)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => onDecide(false),
                    style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    child: const Text('Reject'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => onDecide(true),
                    child: const Text('Approve'),
                  ),
                ],
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    s.status == SubmissionStatus.approved
                        ? Icons.check_circle_outline
                        : Icons.cancel_outlined,
                    size: 16,
                  ),
                  label: Text(
                    '${s.status.displayLabel}'
                    '${s.reviewedByName != null ? ' by ${s.reviewedByName}' : ''}',
                  ),
                ),
              ),
            if (s.decisionRemarks?.trim().isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Remarks: ${s.decisionRemarks}',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }
}
