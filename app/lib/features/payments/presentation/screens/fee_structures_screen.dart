import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../domain/entities/installment.dart';
import '../../domain/entities/fee_structure.dart';
import '../controllers/payment_controller.dart';
import '../widgets/fee_item_editor.dart';
import '../widgets/installment_editor.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// The school's published fee schedules.
///
/// A schedule is a template, so this screen is a Director/Admin surface
/// rather than a cashier's: publishing "Grade 10, SY 2026-2027 — 17,000"
/// is a decision about what the school charges, made once a year, and
/// separate from the act of charging it to a family. The registrar's
/// assessment screen consumes what is published here.
class FeeStructuresScreen extends ConsumerWidget {
  const FeeStructuresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final structuresAsync = ref.watch(feeStructuresProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fee Schedules')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('New schedule'),
      ),
      body: structuresAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load fee schedules: $err')),
        data: (structures) {
          if (structures.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No fee schedules yet.\n\nA schedule is the set of fees a division '
                  'or grade level is charged for a school year. Publish one here and '
                  'the registrar can assess it against a student in two taps, itemised.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: structures.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final structure = structures[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  onTap: () => _openEditor(context, ref, structure),
                  title: Text(structure.name),
                  subtitle: Text(
                    '${structure.appliesToLabel} · SY ${structure.schoolYear}\n'
                    '${structure.items.length} ${structure.items.length == 1 ? 'fee' : 'fees'}'
                    '${structure.isActive ? '' : ' · Retired'}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    _currencyFormat.format(structure.total),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: structure.isActive
                              ? null
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, FeeStructure? structure) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FeeStructureEditorScreen(structure: structure)),
    );
  }
}

/// Creates or edits one schedule.
class FeeStructureEditorScreen extends ConsumerStatefulWidget {
  final FeeStructure? structure;
  const FeeStructureEditorScreen({super.key, this.structure});

  @override
  ConsumerState<FeeStructureEditorScreen> createState() => _FeeStructureEditorScreenState();
}

class _FeeStructureEditorScreenState extends ConsumerState<FeeStructureEditorScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _gradeController;
  late final TextEditingController _yearController;
  late EducationLevel _level;
  late bool _isActive;
  late final List<FeeItemDraft> _items;
  late final List<InstallmentDraft> _installments;

  /// Rows the user removed. Their controllers are still attached to a
  /// TextField for the rest of the frame, and disposing one before the
  /// row unmounts throws "used after being disposed" -- so they wait
  /// here until this screen itself goes away.
  final List<FeeItemDraft> _discarded = [];
  final List<InstallmentDraft> _discardedInstallments = [];
  bool _yearSeeded = false;

  @override
  void initState() {
    super.initState();
    final s = widget.structure;
    _nameController = TextEditingController(text: s?.name ?? '');
    _gradeController = TextEditingController(text: s?.gradeLevel ?? '');
    _yearController = TextEditingController(text: s?.schoolYear ?? '');
    // An existing schedule already carries its year; only a new one
    // wants the school's current one filled in.
    _yearSeeded = s != null;
    _level = s?.educationLevel ?? EducationLevel.elementary;
    _isActive = s?.isActive ?? true;
    _items = [
      for (final item in s?.items ?? const <FeeItem>[]) FeeItemDraft.from(item),
      // A new schedule opens with one blank line rather than an empty
      // list and an "add" button: the first thing anyone does here is
      // type a fee, and making them ask for the field first is a step
      // that exists only because it was easier to build.
      if (s == null) FeeItemDraft.blank(),
    ];
    // No blank row for a new schedule, unlike the fee list above. A plan
    // is optional and most schedules will not have one; opening with an
    // empty row would read as a field that has to be filled in.
    _installments = [
      for (final line in s?.installments ?? const <Installment>[])
        InstallmentDraft.from(line),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gradeController.dispose();
    _yearController.dispose();
    for (final item in [..._items, ..._discarded]) {
      item.dispose();
    }
    for (final line in [..._installments, ..._discardedInstallments]) {
      line.dispose();
    }
    super.dispose();
  }

  double get _total => draftTotal(_items);

  /// Fills the school year in from the branding record once it arrives.
  ///
  /// It cannot simply be read in initState: brandingProvider is a stream,
  /// and the first read of it starts the subscription and hands back
  /// nothing, so a screen opened cold got a blank field and a validation
  /// error on save. Assigning to the controller during build would
  /// notify its listeners mid-build, hence the post-frame callback.
  void _seedSchoolYear() {
    if (_yearSeeded) return;
    final brandingYear = ref.watch(brandingProvider).valueOrNull?.schoolYear?.trim();
    if (brandingYear == null || brandingYear.isEmpty) return;
    _yearSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _yearController.text.isEmpty) _yearController.text = brandingYear;
    });
  }


  /// A new row falls due a month after the last one, or today if it is
  /// the first. Guessing the interval saves the common case -- monthly
  /// billing -- four taps of a date picker per row, and the guess is
  /// visible and one tap to change.
  void _addInstallment() {
    final last = _installments.isEmpty ? null : _installments.last.dueDate;
    final next = last == null
        ? DateTime.now()
        : DateTime(last.year, last.month + 1, last.day);
    setState(() => _installments.add(InstallmentDraft.blank(
          dueDate: next,
          label: DateFormat('MMMM').format(next),
        )));
  }

  /// Divides the fees across the rows that exist, giving the remainder to
  /// the first one.
  ///
  /// The remainder goes to the first rather than the last deliberately: a
  /// plan of 10,000 over three should read 3,333.34 / 3,333.33 / 3,333.33,
  /// so a family who pays the odd centavo pays it at the start rather
  /// than discovering it on the final instalment.
  void _splitEvenly() {
    if (_installments.isEmpty) return;
    final each = ((_total / _installments.length) * 100).floor() / 100;
    final remainder = ((_total - each * _installments.length) * 100).round() / 100;
    setState(() {
      for (var i = 0; i < _installments.length; i++) {
        final amount = i == 0 ? each + remainder : each;
        _installments[i].amountController.text = amount.toStringAsFixed(2);
      }
    });
  }

  Future<void> _save() async {
    final ok = await ref.read(paymentActionControllerProvider.notifier).saveFeeStructure(
          structureId: widget.structure?.id,
          name: _nameController.text,
          educationLevel: _level,
          gradeLevel: _gradeController.text,
          schoolYear: _yearController.text,
          // A line left blank is a line somebody started and did not
          // finish; the use case refuses a zero amount by name, which is
          // a more useful message than silently dropping the row.
          items: [for (final draft in _items) draft.toItem()],
          installments: [for (final draft in _installments) draft.toInstallment()],
          isActive: _isActive,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Fee schedule saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(paymentActionControllerProvider);
    final theme = Theme.of(context);
    // The school year on the branding record is the one every other
    // printed document uses, so a new schedule defaults to it rather
    // than to a guess made from today's date.
    _seedSchoolYear();

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.structure == null ? 'New Fee Schedule' : 'Edit Fee Schedule'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Schedule name',
              hintText: 'e.g. Grade 10 - Full Year',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<EducationLevel>(
            isExpanded: true,
            value: _level,
            decoration: const InputDecoration(labelText: 'Division'),
            items: EducationLevel.values
                .map((l) => DropdownMenuItem(value: l, child: Text(l.displayLabel)))
                .toList(),
            onChanged: (v) => setState(() => _level = v ?? _level),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gradeController,
            decoration: const InputDecoration(
              labelText: 'Grade / year level (optional)',
              helperText: 'Leave blank to cover the whole division.',
              hintText: 'e.g. Grade 10',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _yearController,
            decoration: const InputDecoration(
              labelText: 'School year',
              hintText: 'e.g. 2026-2027',
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
            title: const Text('Offered when assessing'),
            // Retiring rather than deleting: every assessment already
            // made cites this schedule by name, and those have to stay
            // readable after the school stops using it.
            subtitle: const Text(
              'Turn off to retire this schedule. Assessments already made keep it.',
            ),
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(child: Text('Fees', style: theme.textTheme.titleMedium)),
              Text(
                _currencyFormat.format(_total),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _items.length; i++)
            FeeItemRow(
              key: ObjectKey(_items[i]),
              draft: _items[i],
              onChanged: () => setState(() {}),
              // The last remaining line is not removable: a schedule with
              // no fees cannot be saved anyway, and an empty editor gives
              // nothing to type into.
              onRemove: _items.length == 1
                  ? null
                  : () => setState(() => _discarded.add(_items.removeAt(i))),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _items.add(FeeItemDraft.blank())),
            icon: const Icon(Icons.add),
            label: const Text('Add fee'),
          ),
          const Divider(height: 32),
          InstallmentEditor(
            drafts: _installments,
            feesTotal: _total,
            onAdd: _addInstallment,
            onRemove: (i) =>
                setState(() => _discardedInstallments.add(_installments.removeAt(i))),
            onDateChanged: (i, date) => setState(() => _installments[i].dueDate = date),
            onSplitEvenly: _splitEvenly,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: actionState.isLoading ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: actionState.isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save schedule'),
          ),
        ],
      ),
    );
  }
}
