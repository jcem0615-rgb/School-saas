import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show brandingProvider;
import '../../domain/entities/assessment.dart';
import '../../domain/entities/fee_structure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../domain/entities/discount.dart';
import '../../domain/entities/installment.dart';
import '../../domain/entities/subsidy.dart';
import '../controllers/payment_controller.dart';
import '../widgets/discount_editor.dart';
import '../widgets/fee_item_editor.dart';
import '../widgets/subsidy_editor.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
final _dateFormat = DateFormat.yMMMd();

/// Charges fees to one student.
///
/// The screen is built around the fee schedule rather than around a
/// blank form: a registrar assessing forty students for the same grade
/// should be picking the same schedule forty times, not retyping seven
/// fee lines. The copied items stay editable because real enrolments
/// have exceptions -- a scholar whose tuition is waived, a transferee
/// who joins after the field trip -- and the alternative is the office
/// abandoning the schedule and typing everything by hand for the one
/// student in ten who differs.
class AssessFeesScreen extends ConsumerStatefulWidget {
  final String studentId;
  final String studentName;
  final EducationLevel educationLevel;
  final String gradeLevel;

  const AssessFeesScreen({
    super.key,
    required this.studentId,
    required this.studentName,
    required this.educationLevel,
    required this.gradeLevel,
  });

  @override
  ConsumerState<AssessFeesScreen> createState() => _AssessFeesScreenState();
}

class _AssessFeesScreenState extends ConsumerState<AssessFeesScreen> {
  final _remarksController = TextEditingController();
  late final TextEditingController _yearController;

  /// The schedule the draft below was copied from, or null for an ad-hoc
  /// charge. Kept so the assessment records where it came from -- which
  /// is also what the server's duplicate check keys on.
  FeeStructure? _source;
  final List<FeeItemDraft> _items = [];
  final List<DiscountDraft> _discounts = [];
  final List<DiscountDraft> _discardedDiscounts = [];
  final List<SubsidyDraft> _subsidies = [];
  final List<SubsidyDraft> _discardedSubsidies = [];
  final List<FeeItemDraft> _discarded = [];
  bool _yearSeeded = false;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    _yearController.dispose();
    for (final item in [..._items, ..._discarded]) {
      item.dispose();
    }
    for (final discount in [..._discounts, ..._discardedDiscounts]) {
      discount.dispose();
    }
    for (final subsidy in [..._subsidies, ..._discardedSubsidies]) {
      subsidy.dispose();
    }
    super.dispose();
  }

  double get _gross => draftTotal(_items);

  List<FeeItem> get _feeItems => [for (final draft in _items) draft.toItem()];

  List<Discount> get _grantedDiscounts => [
        for (final draft in _discounts)
          if (draft.amountAgainst(_feeItems) > 0)
            draft.toDiscount(_feeItems, _approverName),
      ];

  List<Subsidy> get _recordedSubsidies => [
        for (final draft in _subsidies)
          if (draft.isComplete) draft.toSubsidy(_approverName),
      ];

  /// What is left to charge somebody once the school's own discounts are
  /// off. The grants are checked against this, not against the fees.
  double get _afterDiscounts {
    final left = _gross - totalDiscount(_grantedDiscounts);
    return left < 0 ? 0 : left;
  }

  /// What the *family* is actually charged, which is what the payment
  /// plan has to add up to and what moves the balance. A grant the school
  /// will bill DepEd for is not the family's debt.
  double get _total {
    final net = _afterDiscounts - totalSubsidy(_recordedSubsidies);
    return net < 0 ? 0 : net;
  }

  /// Only for the on-screen preview -- the server stamps the approver
  /// from the caller's own token, so a client cannot grant a scholarship
  /// in somebody else's name.
  String get _approverName =>
      ref.read(authStateProvider).valueOrNull?.fullName ?? 'Unknown';

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


  void _loadStructure(FeeStructure? structure) {
    setState(() {
      _discarded.addAll(_items);
      _items
        ..clear()
        ..addAll([
          for (final item in structure?.items ?? const <FeeItem>[]) FeeItemDraft.from(item),
        ]);
      if (_items.isEmpty) _items.add(FeeItemDraft.blank());
      // Cleared with the rest of the draft. A discount granted to the
      // last student is not a discount granted to this one, and leaving
      // it on screen after a successful charge is how the wrong family
      // gets a scholarship.
      _discardedDiscounts.addAll(_discounts);
      _discounts.clear();
      _discardedSubsidies.addAll(_subsidies);
      _subsidies.clear();
      _source = structure;
      if (structure != null && structure.schoolYear.trim().isNotEmpty) {
        _yearController.text = structure.schoolYear.trim();
        _yearSeeded = true;
      }
    });
  }

  /// The plan this charge will carry, which is the schedule's own plan
  /// only while the fees still add up to it.
  ///
  /// A registrar who waives 2,000 off a line has made the published plan
  /// wrong -- its instalments now total more than the family is being
  /// charged -- and the server refuses that outright. Silently rescaling
  /// the instalments would be worse than refusing: it would move dates
  /// and amounts a family was given in writing, without anybody deciding
  /// to. So an edited charge falls due immediately and the screen says
  /// so, which is at least a fact somebody can act on.
  List<Installment> get _plan {
    final published = _source?.installments ?? const <Installment>[];
    if (published.isEmpty) return const [];
    final planned = published.fold<double>(0, (sum, i) => sum + i.amount);
    return (planned - _total).abs() < 0.01 ? published : const [];
  }

  bool get _planWasDropped =>
      (_source?.installments.isNotEmpty ?? false) && _plan.isEmpty;

  /// The live object for whichever schedule is loaded, or null.
  FeeStructure? _selectedFrom(List<FeeStructure> applicable) {
    for (final structure in applicable) {
      if (structure.id == _source?.id) return structure;
    }
    return null;
  }

  Future<void> _assess(double currentBalance) async {
    final total = _total;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Charge these fees?'),
        content: Text(
          '${widget.studentName} will be charged ${_currencyFormat.format(total)}.\n\n'
          'Balance goes from ${_currencyFormat.format(currentBalance)} to '
          '${_currencyFormat.format(currentBalance + total)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Charge'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final outcome = await ref.read(paymentActionControllerProvider.notifier).assessStudentFees(
          studentId: widget.studentId,
          schoolYear: _yearController.text,
          items: _feeItems,
          installments: _plan,
          discounts: _grantedDiscounts,
          subsidies: _recordedSubsidies,
          sourceStructureId: _source?.id,
          sourceStructureName: _source?.name,
          remarks: _remarksController.text,
        );
    if (!mounted || outcome == null) return;

    // Clearing the draft is the point: leaving the charged items on
    // screen invites a second tap, and charging the same schedule twice
    // is exactly the mistake this screen makes easy.
    _loadStructure(null);
    _remarksController.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Charged ${_currencyFormat.format(outcome.total)}. '
            'New balance ${_currencyFormat.format(outcome.newBalance)}.',
          ),
        ),
      );
  }

  Future<void> _void(Assessment assessment) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Void this assessment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_currencyFormat.format(assessment.total)} comes back off the '
              'balance. The assessment stays on the record, marked voided.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Assessed under the wrong schedule',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(reasonController.text),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Void'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;

    final ok = await ref
        .read(paymentActionControllerProvider.notifier)
        .voidAssessment(assessmentId: assessment.id, reason: reason);
    if (ok && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Assessment voided.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionState = ref.watch(paymentActionControllerProvider);
    _seedSchoolYear();
    final balance = ref.watch(studentBalanceStreamProvider(widget.studentId)).valueOrNull ?? 0;
    final assessmentsAsync = ref.watch(assessmentsForStudentProvider(widget.studentId));
    final structuresAsync = ref.watch(feeStructuresProvider);

    ref.listen(paymentActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    // Only schedules this student could actually be charged under, and
    // only ones still offered. A registrar picking from every schedule
    // the school has ever published is one dropdown slip away from
    // charging a Grade 4 pupil college tuition.
    final applicable = (structuresAsync.valueOrNull ?? const <FeeStructure>[])
        .where((s) =>
            s.isActive &&
            s.appliesTo(level: widget.educationLevel, studentGradeLevel: widget.gradeLevel))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text('Assess Fees - ${widget.studentName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current balance',
                  style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
                ),
                Text(
                  _currencyFormat.format(balance),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Charge a fee schedule', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          structuresAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (err, _) => Text('Failed to load fee schedules: $err'),
            data: (_) => applicable.isEmpty
                ? Text(
                    'No fee schedule is published for '
                    '${widget.educationLevel.displayLabel}'
                    '${widget.gradeLevel.trim().isEmpty ? '' : ' · ${widget.gradeLevel}'} yet. '
                    'You can still charge fees by typing them below.',
                    style: theme.textTheme.bodySmall,
                  )
                : DropdownButtonFormField<FeeStructure?>(
                    isExpanded: true,
                    // Matched by id, not identity: the structures stream
                    // hands back fresh objects on every tick, and an
                    // identity check would blank the dropdown mid-edit
                    // while the copied fee lines stayed on screen.
                    value: _selectedFrom(applicable),
                    decoration: const InputDecoration(labelText: 'Fee schedule'),
                    items: [
                      const DropdownMenuItem<FeeStructure?>(
                        value: null,
                        child: Text('Ad-hoc charge (type the fees)'),
                      ),
                      for (final structure in applicable)
                        DropdownMenuItem<FeeStructure?>(
                          value: structure,
                          child: Text(
                            '${structure.name} - ${_currencyFormat.format(structure.total)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _loadStructure,
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Fees to charge', style: theme.textTheme.titleMedium)),
              Text(
                _currencyFormat.format(_total),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Pick a schedule above, or add a fee to charge something one-off.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          for (var i = 0; i < _items.length; i++)
            FeeItemRow(
              key: ObjectKey(_items[i]),
              draft: _items[i],
              onChanged: () => setState(() {}),
              onRemove: () => setState(() => _discarded.add(_items.removeAt(i))),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _items.add(FeeItemDraft.blank())),
            icon: const Icon(Icons.add),
            label: const Text('Add fee'),
          ),
          const Divider(height: 32),
          DiscountEditor(
            drafts: _discounts,
            items: _feeItems,
            onAdd: () => setState(() => _discounts.add(DiscountDraft.blank())),
            onRemove: (i) =>
                setState(() => _discardedDiscounts.add(_discounts.removeAt(i))),
            onChanged: () => setState(() {}),
          ),
          const Divider(height: 32),
          SubsidyEditor(
            drafts: _subsidies,
            chargeableAfterDiscounts: _afterDiscounts,
            onAdd: () => setState(() => _subsidies.add(SubsidyDraft.blank())),
            onRemove: (i) =>
                setState(() => _discardedSubsidies.add(_subsidies.removeAt(i))),
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_source?.installments.isNotEmpty ?? false) _PlanNotice(
            plan: _plan,
            dropped: _planWasDropped,
          ),
          TextField(
            controller: _remarksController,
            decoration: const InputDecoration(
              labelText: 'Remarks (optional)',
              hintText: 'e.g. Tuition waived under academic scholarship',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: actionState.isLoading || _items.isEmpty || _total <= 0
                ? null
                : () => _assess(balance),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: actionState.isLoading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Charge ${_currencyFormat.format(_total)}'),
          ),
          const Divider(height: 40),
          Text('Assessment history', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          assessmentsAsync.when(
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )),
            error: (err, _) => Text('Failed to load assessments: $err'),
            data: (assessments) => assessments.isEmpty
                ? Text(
                    'Nothing has been assessed to this student yet.',
                    style: theme.textTheme.bodySmall,
                  )
                : Column(
                    children: [
                      for (final assessment in assessments)
                        _AssessmentCard(
                          assessment: assessment,
                          onVoid: assessment.isVoided ? null : () => _void(assessment),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentCard extends StatelessWidget {
  final Assessment assessment;
  final VoidCallback? onVoid;

  const _AssessmentCard({required this.assessment, this.onVoid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voided = assessment.isVoided;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    assessment.sourceLabel,
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: voided ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                Text(
                  _currencyFormat.format(assessment.total),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (onVoid != null)
                  IconButton(
                    icon: const Icon(Icons.block, size: 20),
                    tooltip: 'Void',
                    onPressed: onVoid,
                  ),
              ],
            ),
            Text(
              'SY ${assessment.schoolYear} · ${_dateFormat.format(assessment.assessedAt)} · '
              '${assessment.assessedByName}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            for (final item in assessment.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Expanded(child: Text(item.label, style: theme.textTheme.bodySmall)),
                    Text(_currencyFormat.format(item.amount), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            if (assessment.remarks != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(assessment.remarks!, style: theme.textTheme.bodySmall),
              ),
            if (voided)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Voided by ${assessment.voidedByName ?? 'the office'}'
                  '${assessment.voidReason == null ? '' : ' - ${assessment.voidReason}'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// What the family will be told about when to pay.
///
/// Shown only when the chosen schedule publishes a plan, so a school
/// billing in one lump never sees it.
class _PlanNotice extends StatelessWidget {
  final List<Installment> plan;
  final bool dropped;

  const _PlanNotice({required this.plan, required this.dropped});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueFormat = DateFormat('d MMM');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: dropped
              ? theme.colorScheme.errorContainer
              : theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dropped ? 'No payment plan will be attached' : 'Payment plan',
              style: theme.textTheme.labelLarge?.copyWith(
                color: dropped ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              dropped
                  ? 'The fees above no longer add up to the schedule\'s plan, so '
                      'the whole amount will fall due immediately. Put the fees '
                      'back to match the schedule, or edit the plan on the '
                      'schedule itself.'
                  : plan
                      .map((i) => '${i.label} ${dueFormat.format(i.dueDate)} '
                          '${_currencyFormat.format(i.amount)}')
                      .join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: dropped ? theme.colorScheme.onErrorContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
