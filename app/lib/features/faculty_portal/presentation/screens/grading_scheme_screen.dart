import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/grading_scheme.dart';
import '../controllers/faculty_controller.dart';

final _dateFormat = DateFormat('d MMM y');

/// Where a school says what its grades are made of.
///
/// The weights are seeded with the DepEd Order 8, s. 2015 groupings and
/// they are still not this software's assertion about anybody's grades.
/// Orders are superseded, tracks are added, and a private school may run
/// its own approved scheme -- so the numbers are editable, and nothing is
/// treated as checked until a named person here says it is. Until then
/// grades compute and show on screen marked provisional, and the report
/// card will not print.
class GradingSchemeScreen extends ConsumerStatefulWidget {
  const GradingSchemeScreen({super.key});

  @override
  ConsumerState<GradingSchemeScreen> createState() => _GradingSchemeScreenState();
}

class _GradingSchemeScreenState extends ConsumerState<GradingSchemeScreen> {
  /// The scheme being edited. Null until the stored one arrives, so an
  /// empty form can never be saved over a real scheme.
  List<_GroupDraft>? _groups;
  List<_BandDraft>? _bands;
  bool _dirty = false;

  void _seedFrom(GradingScheme scheme) {
    _groups = [for (final w in scheme.weights) _GroupDraft.from(w)];
    _bands = [for (final b in scheme.transmutation) _BandDraft.from(b)];
  }

  GradingScheme get _draft => GradingScheme(
        weights: [for (final g in _groups ?? const <_GroupDraft>[]) g.toWeights()],
        transmutation: [for (final b in _bands ?? const <_BandDraft>[]) b.toBand()],
      );

  Future<void> _save() async {
    final ok = await ref
        .read(facultyActionControllerProvider.notifier)
        .saveGradingScheme(_draft);
    if (!mounted) return;
    if (ok) {
      setState(() => _dirty = false);
      _say('Saved. Nobody has confirmed these yet, so report cards will not print.');
    }
  }

  Future<void> _confirm(GradingScheme stored) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm the grading scheme'),
        content: const Text(
          'You are saying these weights and this transmutation table are '
          'the ones your school is required to use, checked against the '
          'order that is current for you.\n\n'
          'Your name and the date are recorded against them, and every '
          'grade and report card the school issues is computed this way '
          'until somebody changes it.',
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
        .read(facultyActionControllerProvider.notifier)
        .confirmGradingScheme(stored);
    if (!mounted) return;
    if (ok) _say('Confirmed. Report cards can be printed.');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schemeAsync = ref.watch(gradingSchemeProvider);

    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    // Reseeding only while nothing is half-typed: a stream that emits
    // after somebody has started editing must not wipe what they wrote.
    schemeAsync.whenData((scheme) {
      if (_groups == null || !_dirty) {
        _seedFrom(scheme);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Grading Scheme')),
      body: schemeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load the scheme: $error')),
        data: (stored) {
          final groups = _groups ?? const <_GroupDraft>[];
          final unbalanced = _draft.unbalanced;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ConfirmationCard(
                stored: stored,
                dirty: _dirty,
                blocked: unbalanced.isNotEmpty,
                onConfirm: () => _confirm(stored),
              ),
              const SizedBox(height: 20),

              Text('Subject groups', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'A subject is matched against these in order. The group with '
                'no subjects listed is the catch-all for everything else.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),

              for (var i = 0; i < groups.length; i++)
                _GroupCard(
                  draft: groups[i],
                  onChanged: () => setState(() => _dirty = true),
                  onRemove: groups.length == 1
                      ? null
                      : () => setState(() {
                            _groups!.removeAt(i);
                            _dirty = true;
                          }),
                ),

              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _groups!.add(_GroupDraft.blank());
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add a group'),
              ),

              const SizedBox(height: 24),
              Text('Transmutation', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'An initial grade inside a band becomes the grade beside it. '
                'Leave the table empty if your school reports the computed '
                'grade as it stands -- an empty table is a real setting, not '
                'a missing one.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < (_bands ?? const <_BandDraft>[]).length; i++)
                _BandRow(
                  draft: _bands![i],
                  onChanged: () => setState(() => _dirty = true),
                  onRemove: () => setState(() {
                    _bands!.removeAt(i);
                    _dirty = true;
                  }),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _bands!.add(_BandDraft.blank());
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add a band'),
              ),

              const SizedBox(height: 24),
              if (unbalanced.isNotEmpty)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'These do not add up to 100 per cent: '
                      '${unbalanced.map((w) => w.label).join(', ')}. '
                      'Weights that do not balance produce grades that look '
                      'right and are wrong for the whole year.',
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !_dirty || unbalanced.isNotEmpty ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save changes'),
              ),
              const SizedBox(height: 8),
              Text(
                'Saving clears the confirmation. Somebody has to check the '
                'new numbers and confirm them again before report cards '
                'print.',
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

class _ConfirmationCard extends StatelessWidget {
  final GradingScheme stored;
  final bool dirty;
  final bool blocked;
  final VoidCallback onConfirm;

  const _ConfirmationCard({
    required this.stored,
    required this.dirty,
    required this.blocked,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmed = stored.confirmedBySchool && !dirty;

    return Card(
      color: confirmed
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(confirmed ? Icons.verified_outlined : Icons.pending_outlined),
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
                  : dirty
                      ? 'There are unsaved changes. Save them, then confirm.'
                      : 'These are the DepEd Order 8, s. 2015 groupings as a '
                          'starting point. Check them against the order that '
                          'applies to your school, change anything that '
                          'differs, then confirm. Report cards will not print '
                          'until somebody does.',
              style: theme.textTheme.bodyMedium,
            ),
            if (!confirmed) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: dirty || blocked ? null : onConfirm,
                child: const Text('Confirm these weights'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final _GroupDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  const _GroupCard({required this.draft, required this.onChanged, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = draft.total;
    final balances = (total - 100).abs() < 0.01;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: balances ? theme.colorScheme.outlineVariant : theme.colorScheme.error,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: draft.label,
                  decoration: const InputDecoration(labelText: 'Group name'),
                  onChanged: (_) => onChanged(),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove this group',
                  onPressed: onRemove,
                ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: draft.subjects,
              decoration: const InputDecoration(
                labelText: 'Subjects, separated by commas',
                hintText: 'Leave empty to catch everything not listed elsewhere',
              ),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _weightField(draft.written, 'Written Work %', onChanged)),
              const SizedBox(width: 8),
              Expanded(child: _weightField(draft.performance, 'Performance %', onChanged)),
              const SizedBox(width: 8),
              Expanded(child: _weightField(draft.quarterly, 'Quarterly %', onChanged)),
            ]),
            const SizedBox(height: 6),
            Text(
              balances
                  ? 'Adds up to 100.'
                  : 'Adds up to ${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 1)}, not 100.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: balances ? null : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _weightField(
    TextEditingController controller,
    String label,
    VoidCallback onChanged,
  ) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => onChanged(),
      );
}

class _BandRow extends StatelessWidget {
  final _BandDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _BandRow({required this.draft, required this.onChanged, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: draft.from,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'From'),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: draft.to,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'To'),
            onChanged: (_) => onChanged(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: draft.transmuted,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Becomes'),
            onChanged: (_) => onChanged(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove this band',
          onPressed: onRemove,
        ),
      ]),
    );
  }
}

/// One group being edited.
class _GroupDraft {
  final TextEditingController label;
  final TextEditingController subjects;
  final TextEditingController written;
  final TextEditingController performance;
  final TextEditingController quarterly;

  _GroupDraft({
    required this.label,
    required this.subjects,
    required this.written,
    required this.performance,
    required this.quarterly,
  });

  factory _GroupDraft.from(SubjectWeights weights) => _GroupDraft(
        label: TextEditingController(text: weights.label),
        subjects: TextEditingController(text: weights.subjects.join(', ')),
        written: TextEditingController(text: _number(weights.writtenWork)),
        performance: TextEditingController(text: _number(weights.performanceTask)),
        quarterly: TextEditingController(text: _number(weights.quarterlyAssessment)),
      );

  factory _GroupDraft.blank() => _GroupDraft(
        label: TextEditingController(),
        subjects: TextEditingController(),
        written: TextEditingController(text: '30'),
        performance: TextEditingController(text: '50'),
        quarterly: TextEditingController(text: '20'),
      );

  double get total =>
      _parse(written) + _parse(performance) + _parse(quarterly);

  SubjectWeights toWeights() => SubjectWeights(
        label: label.text.trim().isEmpty ? 'Subjects' : label.text.trim(),
        subjects: [
          for (final part in subjects.text.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ],
        writtenWork: _parse(written),
        performanceTask: _parse(performance),
        quarterlyAssessment: _parse(quarterly),
      );

  static double _parse(TextEditingController c) =>
      double.tryParse(c.text.trim()) ?? 0;

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
}

/// One transmutation band being edited.
class _BandDraft {
  final TextEditingController from;
  final TextEditingController to;
  final TextEditingController transmuted;

  _BandDraft({required this.from, required this.to, required this.transmuted});

  factory _BandDraft.from(TransmutationBand band) => _BandDraft(
        from: TextEditingController(text: _GroupDraft._number(band.from)),
        to: TextEditingController(text: _GroupDraft._number(band.to)),
        transmuted: TextEditingController(text: '${band.transmuted}'),
      );

  factory _BandDraft.blank() => _BandDraft(
        from: TextEditingController(),
        to: TextEditingController(),
        transmuted: TextEditingController(),
      );

  TransmutationBand toBand() => TransmutationBand(
        from: double.tryParse(from.text.trim()) ?? 0,
        to: double.tryParse(to.text.trim()) ?? 0,
        transmuted: int.tryParse(transmuted.text.trim()) ?? 0,
      );
}
