import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart'
    show brandingProvider, employeesStreamProvider;
import '../../../admin_portal/domain/entities/employee_summary.dart';
import '../../domain/entities/contribution_scheme.dart';
import '../../domain/entities/payslip.dart';
import '../controllers/payroll_controller.dart';
import '../documents/payslip_pdf.dart';
import 'payroll_setup_screen.dart';

final _month = DateFormat('MMMM y');
final _amount = NumberFormat('#,##0.00');

/// A payroll run: pick the month, see what everybody comes to, issue.
///
/// Draft first, issue second, and the two are separate acts. A payslip
/// is a statement of what was paid on a date -- the rules deny editing
/// one afterwards -- so the screen shows the whole run before anything
/// is written, and the numbers on it are the numbers that will be
/// stored.
class PayrollRunScreen extends ConsumerStatefulWidget {
  const PayrollRunScreen({super.key});

  @override
  ConsumerState<PayrollRunScreen> createState() => _PayrollRunScreenState();
}

class _PayrollRunScreenState extends ConsumerState<PayrollRunScreen> {
  DateTime _period = DateTime(DateTime.now().year, DateTime.now().month);
  bool _deductContributions = true;
  bool _working = false;

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _issue(List<Payslip> drafts, ContributionScheme scheme) async {
    final total = drafts.fold<double>(0, (sum, p) => sum + p.netPay);
    final incomplete = drafts.where((p) => p.hoursAreIncomplete).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Issue ${drafts.length} payslips?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_month.format(_period)} — net pay '
                '${_amount.format(total)} in total.'),
            const SizedBox(height: 12),
            const Text(
              'A payslip cannot be edited afterwards. A correction is a fresh '
              'one, which is what makes the record worth keeping.',
            ),
            if (incomplete > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$incomplete of these have days that were scanned in and never '
                'out. Those hours are not known and are not paid.',
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Issue'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final issued = await ref
        .read(payrollActionControllerProvider.notifier)
        .issuePayslips(payslips: drafts, scheme: scheme);
    if (!mounted) return;
    setState(() => _working = false);
    if (issued != null) _say('$issued payslips issued.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = ref.watch(contributionSchemeProvider).valueOrNull;
    final compensation =
        ref.watch(compensationStreamProvider).valueOrNull ?? const <Compensation>[];
    final employees =
        ref.watch(employeesStreamProvider).valueOrNull ?? const <EmployeeSummary>[];
    // Watched so the letterhead has arrived before anybody prints.
    final branding = ref.watch(brandingProvider).valueOrNull ?? SchoolBranding.empty;

    ref.listen(payrollActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    final drafts = <Payslip>[];
    for (final person in compensation) {
      final draft = ref.watch(payslipDraftProvider(PayrollDraftQuery(
        compensation: person,
        month: _period,
        deductContributions: _deductContributions,
      )));
      if (draft != null) drafts.add(draft);
    }

    final unpaid = employees
        .where((e) => !compensation.any((c) => c.employeeUid == e.uid))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Payroll setup',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PayrollSetupScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: drafts.isEmpty || scheme == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _working ? null : () => _issue(drafts, scheme),
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text('Issue ${drafts.length}'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_working) const LinearProgressIndicator(),

          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(
                    () => _period = DateTime(_period.year, _period.month - 1)),
                icon: const Icon(Icons.chevron_left),
                label: Text(_month.format(_period)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                  () => _period = DateTime(_period.year, _period.month + 1)),
            ),
          ]),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _deductContributions,
            onChanged: (value) => setState(() => _deductContributions = value),
            title: const Text('Deduct contributions this cut-off'),
            // The switch exists because taking the month's contributions
            // on both halves of a semi-monthly payroll takes double from
            // everybody, and it is the kind of mistake nobody notices
            // until somebody checks their own payslip.
            subtitle: const Text(
              'Turn off for the first cut-off of a semi-monthly month, so the '
              'month\'s contributions are not taken twice.',
            ),
          ),

          if (scheme != null && !scheme.canIssuePayslips)
            Card(
              color: theme.colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_outlined),
                title: const Text('The contribution tables are not confirmed'),
                subtitle: Text(
                  scheme.isComplete
                      ? 'They are filled in but nobody has confirmed them. '
                          'Nothing will issue until somebody does.'
                      : 'Still empty: '
                          '${scheme.unconfiguredKinds.map((k) => k.displayLabel).join(', ')}.',
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PayrollSetupScreen()),
                ),
              ),
            ),

          const SizedBox(height: 12),
          if (drafts.isNotEmpty)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _amount.format(
                          drafts.fold<double>(0, (sum, p) => sum + p.netPay)),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'net pay across ${drafts.length} staff for '
                      '${_month.format(_period)}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                    // The school's own share, which never appears on a
                    // payslip and is money it has to have.
                    Text(
                      'Employer share to remit: ${_amount.format(drafts.fold<double>(0, (sum, p) => sum + p.employerContributions))}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),
          if (compensation.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nobody has a pay rate on file yet. Set one from Employee '
                'Management and they appear here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            for (final draft in drafts)
              _PayslipTile(payslip: draft, branding: branding),

          if (unpaid.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('No pay rate on file', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            // Named rather than silently skipped. Somebody missing from
            // a payroll run is the failure nobody notices until payday.
            Text(
              'These staff are not in this run because nothing says what they '
              'are paid.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final employee in unpaid)
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text('${employee.firstName} ${employee.lastName}'),
                subtitle: Text(employee.role.displayName),
              ),
          ],
        ],
      ),
    );
  }
}

class _PayslipTile extends StatelessWidget {
  final Payslip payslip;
  final SchoolBranding branding;

  const _PayslipTile({required this.payslip, required this.branding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: payslip.hoursAreIncomplete
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: ExpansionTile(
        title: Text(payslip.employeeName),
        subtitle: Text(
          '${payslip.daysWorked} days worked'
          '${payslip.daysAbsent > 0 ? ', ${payslip.daysAbsent} absent' : ''}'
          '${payslip.daysLate > 0 ? ', ${payslip.daysLate} late' : ''}',
        ),
        trailing: Text(
          _amount.format(payslip.netPay),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        children: [
          for (final line in payslip.earnings)
            _line(context, line.label, line.amount, line.basis),
          for (final line in payslip.deductions)
            _line(context, line.label, -line.amount, line.basis),
          if (payslip.hoursAreIncomplete)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                '${payslip.daysMissingTimeOut} day(s) scanned in and never out. '
                'Those hours are not known, so they are not paid.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      PayslipPdf.print(payslip: payslip, branding: branding),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String label, double amount, String? basis) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  if (basis != null && basis.isNotEmpty)
                    Text(basis, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Text(_amount.format(amount)),
          ],
        ),
      );
}
