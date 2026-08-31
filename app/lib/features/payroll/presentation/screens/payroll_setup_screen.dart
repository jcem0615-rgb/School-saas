import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/contribution_scheme.dart';
import '../controllers/payroll_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// Where a school types in what the agencies take.
///
/// Nothing is seeded. The grading scheme ships with the DepEd groupings
/// filled in because those are four coarse numbers that have been stable
/// for a decade; these are not. SSS, PhilHealth and Pag-IBIG move most
/// years, the withholding table moved with TRAIN and will move again,
/// and a wrong bracket looks entirely plausible on a payslip. The
/// failure is not an out-of-date grade — it is somebody short every
/// payday, or handed a bill at the end of the year.
///
/// So the school types the rows from the circular in front of them,
/// records which circular that was, and confirms. No payslip is issued
/// until they have.
class PayrollSetupScreen extends ConsumerStatefulWidget {
  const PayrollSetupScreen({super.key});

  @override
  ConsumerState<PayrollSetupScreen> createState() => _PayrollSetupScreenState();
}

class _PayrollSetupScreenState extends ConsumerState<PayrollSetupScreen> {
  Map<ContributionKind, _TableDraft>? _drafts;
  bool _dirty = false;

  void _seedFrom(ContributionScheme scheme) {
    _drafts = {
      for (final kind in ContributionKind.values)
        kind: _TableDraft.from(scheme.tableFor(kind)),
    };
  }

  ContributionScheme get _draft => ContributionScheme(
        tables: [
          for (final entry in (_drafts ?? {}).entries) entry.value.toTable(entry.key),
        ],
      );

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final ok = await ref
        .read(payrollActionControllerProvider.notifier)
        .saveContributionScheme(_draft);
    if (!mounted) return;
    if (ok) {
      setState(() => _dirty = false);
      _say('Saved. Nobody has confirmed these yet, so no payslip will issue.');
    }
  }

  Future<void> _confirm(ContributionScheme stored) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm the contribution tables'),
        content: const Text(
          'You are saying these are the rates your school is required to '
          'deduct, checked against the circulars that are current for you.\n\n'
          'Your name and the date are recorded against them, and every '
          'payslip the school issues deducts this way until somebody '
          'changes it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('These are correct'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    final ok = await ref
        .read(payrollActionControllerProvider.notifier)
        .confirmContributionScheme(stored);
    if (!mounted) return;
    if (ok) _say('Confirmed. Payslips can be issued.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schemeAsync = ref.watch(contributionSchemeProvider);

    ref.listen(payrollActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    schemeAsync.whenData((scheme) {
      // Reseed only while nothing is half-typed, so a stream emitting
      // mid-edit cannot wipe what somebody has written.
      if (_drafts == null || !_dirty) _seedFrom(scheme);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Payroll Setup')),
      body: schemeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load the tables: $error')),
        data: (stored) {
          final draft = _draft;
          final confirmed = stored.confirmedBySchool && !_dirty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: confirmed
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(confirmed
                            ? Icons.verified_outlined
                            : Icons.pending_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            confirmed ? 'Confirmed by the school' : 'Not confirmed yet',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        confirmed
                            ? 'Checked by ${stored.confirmedByName ?? 'somebody at the school'}'
                                '${stored.confirmedAt == null ? '' : ' on ${_dateFormat.format(stored.confirmedAt!)}'}.'
                            : _dirty
                                ? 'There are unsaved changes. Save them, then confirm.'
                                : 'Nothing here is seeded. These rates change most '
                                    'years and a wrong bracket looks entirely '
                                    'plausible on a payslip, so this software does '
                                    'not guess at them. Type the rows from the '
                                    'circular in front of you, note which circular '
                                    'it was, and confirm.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (!confirmed) ...[
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _dirty || !draft.isComplete
                              ? null
                              : () => _confirm(stored),
                          child: const Text('Confirm these tables'),
                        ),
                        if (draft.unconfiguredKinds.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Still empty: '
                              '${draft.unconfiguredKinds.map((k) => k.displayLabel).join(', ')}. '
                              'A payslip that silently deducts nothing for an '
                              'agency is one the school under-remits on all year.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              for (final kind in ContributionKind.values)
                _TableCard(
                  kind: kind,
                  draft: (_drafts ?? {})[kind]!,
                  onChanged: () => setState(() => _dirty = true),
                ),

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !_dirty ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save tables'),
              ),
              const SizedBox(height: 8),
              Text(
                'Saving clears the confirmation. Somebody has to check the new '
                'numbers and confirm them again before the next payslip.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  final ContributionKind kind;
  final _TableDraft draft;
  final VoidCallback onChanged;

  const _TableCard({required this.kind, required this.draft, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kind.displayLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: draft.sourceLabel,
              decoration: const InputDecoration(
                labelText: 'Which circular these came from',
                hintText: 'SSS Circular 2025-006, RR 8-2018',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 4),
            Text(
              'Printed beside the deduction, so an employee asking why it is '
              'that amount has somewhere to look.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < draft.rows.length; i++)
              _BracketRow(
                row: draft.rows[i],
                onChanged: onChanged,
                onRemove: () {
                  draft.rows.removeAt(i);
                  onChanged();
                },
              ),
            if (draft.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No brackets yet. Nothing is deducted for '
                  '${kind.displayLabel} until there are.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () {
                draft.rows.add(_BracketDraft.blank());
                onChanged();
              },
              icon: const Icon(Icons.add),
              label: const Text('Add a bracket'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BracketRow extends StatelessWidget {
  final _BracketDraft row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _BracketRow({
    required this.row,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: label, isDense: true),
            onChanged: (_) => onChanged(),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          Row(children: [
            field(row.from, 'Salary from'),
            const SizedBox(width: 6),
            field(row.to, 'to (blank = no cap)'),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove this bracket',
              onPressed: onRemove,
            ),
          ]),
          Row(children: [
            field(row.fixedAmount, 'Employee amount'),
            const SizedBox(width: 6),
            field(row.percentOfExcess, '+ % of excess'),
            const SizedBox(width: 6),
            field(row.employerFixedAmount, 'Employer amount'),
            const SizedBox(width: 6),
            field(row.employerPercentOfExcess, '+ % of excess'),
          ]),
        ],
      ),
    );
  }
}

class _TableDraft {
  final TextEditingController sourceLabel;
  final List<_BracketDraft> rows;

  _TableDraft({required this.sourceLabel, required this.rows});

  factory _TableDraft.from(ContributionTable table) => _TableDraft(
        sourceLabel: TextEditingController(text: table.sourceLabel ?? ''),
        rows: [for (final b in table.brackets) _BracketDraft.from(b)],
      );

  ContributionTable toTable(ContributionKind kind) => ContributionTable(
        kind: kind,
        sourceLabel: sourceLabel.text.trim().isEmpty ? null : sourceLabel.text.trim(),
        brackets: [for (final row in rows) row.toBracket()],
      );
}

class _BracketDraft {
  final TextEditingController from;
  final TextEditingController to;
  final TextEditingController fixedAmount;
  final TextEditingController percentOfExcess;
  final TextEditingController employerFixedAmount;
  final TextEditingController employerPercentOfExcess;

  _BracketDraft({
    required this.from,
    required this.to,
    required this.fixedAmount,
    required this.percentOfExcess,
    required this.employerFixedAmount,
    required this.employerPercentOfExcess,
  });

  factory _BracketDraft.from(ContributionBracket b) => _BracketDraft(
        from: TextEditingController(text: _number(b.from)),
        to: TextEditingController(text: b.to == null ? '' : _number(b.to!)),
        fixedAmount: TextEditingController(text: _number(b.fixedAmount)),
        percentOfExcess: TextEditingController(text: _number(b.percentOfExcess)),
        employerFixedAmount: TextEditingController(text: _number(b.employerFixedAmount)),
        employerPercentOfExcess:
            TextEditingController(text: _number(b.employerPercentOfExcess)),
      );

  factory _BracketDraft.blank() => _BracketDraft(
        from: TextEditingController(),
        to: TextEditingController(),
        fixedAmount: TextEditingController(),
        percentOfExcess: TextEditingController(),
        employerFixedAmount: TextEditingController(),
        employerPercentOfExcess: TextEditingController(),
      );

  ContributionBracket toBracket() => ContributionBracket(
        from: double.tryParse(from.text.trim()) ?? 0,
        // Blank means no ceiling, which is what the top bracket is.
        to: to.text.trim().isEmpty ? null : double.tryParse(to.text.trim()),
        fixedAmount: double.tryParse(fixedAmount.text.trim()) ?? 0,
        percentOfExcess: double.tryParse(percentOfExcess.text.trim()) ?? 0,
        employerFixedAmount: double.tryParse(employerFixedAmount.text.trim()) ?? 0,
        employerPercentOfExcess:
            double.tryParse(employerPercentOfExcess.text.trim()) ?? 0,
      );

  static String _number(double value) =>
      value == 0 ? '' : (value == value.roundToDouble()
          ? value.toStringAsFixed(0)
          : value.toString());
}
