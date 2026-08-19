import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/invoice.dart';
import '../../domain/entities/school_summary.dart';
import '../controllers/owner_controller.dart';
import '../widgets/school_status_badge.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat.yMMMd();

/// Owner's drill-down for a single school: current billing status,
/// pause/resume control, and invoice history. Pause/Resume are the two
/// actions from the spec that must "take effect immediately" -- both are
/// wired straight to Cloud Functions rather than local state so there's
/// no risk of a client-only toggle drifting from the server's billing
/// engine's understanding of the school's status.
class SchoolDetailScreen extends ConsumerWidget {
  final String schoolId;
  const SchoolDetailScreen({super.key, required this.schoolId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsAsync = ref.watch(schoolsStreamProvider);
    final invoicesAsync = ref.watch(invoicesStreamProvider(schoolId));
    final actionState = ref.watch(ownerActionControllerProvider);

    ref.listen(ownerActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('School Details')),
      body: schoolsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load: $err')),
        data: (schools) {
          final matches = schools.where((s) => s.id == schoolId);
          final school = matches.isEmpty ? null : matches.first;
          if (school == null) {
            return const Center(child: Text('School not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(school.name, style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  SchoolStatusBadge(status: school.status),
                ],
              ),
              const SizedBox(height: 4),
              Text('${school.activeStudentCount} active students · ${_currencyFormat.format(school.currentCycleAccrued)} accrued this cycle'),
              const SizedBox(height: 24),
              _buildActionButton(context, ref, school, actionState.isLoading),
              const SizedBox(height: 32),
              Text('Invoices', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              invoicesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Failed to load invoices: $err'),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return const Text('No invoices yet.');
                  }
                  return Column(
                    children: invoices.map((inv) => _InvoiceTile(schoolId: schoolId, invoice: inv)).toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    WidgetRef ref,
    SchoolSummary school,
    bool isLoading,
  ) {
    if (school.status == SchoolSubscriptionStatus.suspended ||
        school.status == SchoolSubscriptionStatus.gracePeriod) {
      return FilledButton.icon(
        onPressed: isLoading ? null : () => ref.read(ownerActionControllerProvider.notifier).resumeSchool(schoolId),
        icon: const Icon(Icons.play_circle_outline),
        label: const Text('Resume School'),
      );
    }
    return OutlinedButton.icon(
      onPressed: isLoading ? null : () => _showPauseDialog(context, ref),
      icon: const Icon(Icons.pause_circle_outline),
      label: const Text('Pause School'),
      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
    );
  }

  Future<void> _showPauseDialog(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pause this school?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Students, staff, and parents at this school will immediately lose access.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Pause'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(ownerActionControllerProvider.notifier).pauseSchool(
            schoolId: schoolId,
            reason: reasonController.text,
          );
    }
  }
}

class _InvoiceTile extends ConsumerWidget {
  final String schoolId;
  final Invoice invoice;
  const _InvoiceTile({required this.schoolId, required this.invoice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label =
        '${_dateFormat.format(invoice.billingPeriodStart)} - ${_dateFormat.format(invoice.billingPeriodEnd)}';
    final (Color color, IconData icon) = switch (invoice.status) {
      InvoiceStatus.paid => (Colors.green, Icons.check_circle_outline),
      InvoiceStatus.pending => (Colors.blueGrey, Icons.hourglass_empty),
      InvoiceStatus.overdue => (Colors.red, Icons.warning_amber_outlined),
      InvoiceStatus.void_ => (Colors.grey, Icons.block),
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(_currencyFormat.format(invoice.totalAmount)),
        subtitle: Text(label),
        trailing: Text(invoice.status.value.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
