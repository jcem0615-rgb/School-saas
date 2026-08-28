import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/system_check.dart';
import '../controllers/system_check_controller.dart';

final _timestamp = DateFormat('d MMM y, h:mm a');

/// Runs the preflight and shows what it found.
///
/// Built for the half hour before a school is let in. Every check that
/// fails here is one that would otherwise be found by a registrar on a
/// Monday morning, in front of a parent, with no idea what to do about
/// it.
class SystemCheckScreen extends ConsumerWidget {
  const SystemCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(systemCheckControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('System Check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Before a school starts using this for real, these are the things '
            'that have to be true. Nothing here changes the school\'s data: '
            'the probes call each function with arguments it must refuse, and '
            'attempt a write the rules must refuse.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: state.isLoading
                ? null
                : () => ref.read(systemCheckControllerProvider.notifier).run(),
            icon: state.isLoading
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(state.isLoading ? 'Checking…' : 'Run the checks'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 20),
          state.when(
            loading: () => Text(
              'Calling each function and probing the rules. This takes a '
              'moment -- a function that is not deployed has to time out '
              'before it can be reported.',
              style: theme.textTheme.bodySmall,
            ),
            error: (err, _) => _Banner(
              status: CheckStatus.fail,
              title: 'The check could not run',
              detail: '$err',
            ),
            data: (report) =>
                report == null ? const SizedBox.shrink() : _Report(report: report),
          ),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  final SystemCheckReport report;
  const _Report({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.demoMode)
          const _Banner(
            status: CheckStatus.warn,
            title: 'Nothing was checked',
            // A preflight that goes green against an in-memory store is a
            // green light that means nothing, shown to the one person
            // who most needs it to mean something.
            detail: 'This build is running in demo mode against an in-memory '
                'store. There is no Firebase project here to check. Build with '
                'DEMO_MODE=false against the real project and run this again.',
          )
        else
          _Banner(
            status: report.failures > 0
                ? CheckStatus.fail
                : report.warnings > 0
                    ? CheckStatus.warn
                    : CheckStatus.pass,
            title: report.headline,
            detail: report.failures > 0
                ? 'Do not let a school in until these pass. Each one is a '
                    'fault that is invisible until somebody hits the screen '
                    'that needs it.'
                : report.warnings > 0
                    ? 'The deployment works. The items below are worth '
                        'settling before a school starts.'
                    : 'Every check passed.',
          ),
        const SizedBox(height: 8),
        Text(
          'Run ${_timestamp.format(report.ranAt)}',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final check in report.checks) _CheckTile(check: check),
      ],
    );
  }
}

class _CheckTile extends StatelessWidget {
  final SystemCheck check;
  const _CheckTile({required this.check});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour) = switch (check.status) {
      CheckStatus.pass => (Icons.check_circle_outline, Colors.green),
      CheckStatus.warn => (Icons.error_outline, Colors.orange),
      CheckStatus.fail => (Icons.cancel_outlined, theme.colorScheme.error),
    };

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colour, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(check.title, style: theme.textTheme.titleSmall),
                  Text(check.detail, style: theme.textTheme.bodySmall),
                  if (check.remedy != null) ...[
                    const SizedBox(height: 8),
                    // The remedy is selectable because most of them are a
                    // command somebody has to type into a terminal.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        check.remedy!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final CheckStatus status;
  final String title;
  final String detail;

  const _Banner({required this.status, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = switch (status) {
      CheckStatus.pass => theme.colorScheme.primaryContainer,
      CheckStatus.warn => theme.colorScheme.surfaceContainerHighest,
      CheckStatus.fail => theme.colorScheme.errorContainer,
    };
    final foreground = switch (status) {
      CheckStatus.pass => theme.colorScheme.onPrimaryContainer,
      CheckStatus.warn => theme.colorScheme.onSurface,
      CheckStatus.fail => theme.colorScheme.onErrorContainer,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(color: foreground)),
          const SizedBox(height: 4),
          Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
        ],
      ),
    );
  }
}
