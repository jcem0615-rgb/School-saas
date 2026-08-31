import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../admin_portal/domain/entities/program.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart'
    show programsStreamProvider;
import '../../domain/entities/applicant.dart';
import '../controllers/admissions_controller.dart';
import 'admissions_screen.dart' show formatAdmissionDate;

/// One family: their details, where they are, and the one step they can
/// be moved to next.
///
/// The actions are the stages the pipeline allows from where they are and
/// nothing else. A screen offering every stage would let somebody mark a
/// family as offered because that is the outcome they expect, and the
/// funnel would then report offers the school never made.
class ApplicantDetailScreen extends ConsumerStatefulWidget {
  /// Null for a new enquiry.
  final Applicant? applicant;
  const ApplicantDetailScreen({super.key, this.applicant});

  @override
  ConsumerState<ApplicantDetailScreen> createState() => _ApplicantDetailScreenState();
}

class _ApplicantDetailScreenState extends ConsumerState<ApplicantDetailScreen> {
  late final _firstName = TextEditingController(text: widget.applicant?.firstName ?? '');
  late final _lastName = TextEditingController(text: widget.applicant?.lastName ?? '');
  late final _middleName = TextEditingController(text: widget.applicant?.middleName ?? '');
  late final _gradeLevel = TextEditingController(text: widget.applicant?.gradeLevel ?? '');
  late final _guardianName =
      TextEditingController(text: widget.applicant?.guardianName ?? '');
  late final _guardianPhone =
      TextEditingController(text: widget.applicant?.guardianPhone ?? '');
  late final _guardianEmail =
      TextEditingController(text: widget.applicant?.guardianEmail ?? '');
  late final _source = TextEditingController(text: widget.applicant?.source ?? '');
  late final _notes = TextEditingController(text: widget.applicant?.notes ?? '');

  late EducationLevel _level =
      widget.applicant?.educationLevel ?? EducationLevel.elementary;
  late String? _programId = widget.applicant?.programId;
  bool _working = false;

  /// The applicant as it now stands. Read from the live list rather than
  /// held, so a stage moved on this screen is reflected without popping
  /// back out to the pipeline and in again.
  Applicant? get _current {
    final id = widget.applicant?.id;
    if (id == null) return null;
    final all = ref.watch(applicantsStreamProvider).valueOrNull ?? const <Applicant>[];
    for (final a in all) {
      if (a.id == id) return a;
    }
    return widget.applicant;
  }

  @override
  void dispose() {
    for (final c in [
      _firstName, _lastName, _middleName, _gradeLevel,
      _guardianName, _guardianPhone, _guardianEmail, _source, _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    setState(() => _working = true);
    final saved = await ref.read(admissionsActionControllerProvider.notifier).saveApplicant(
          applicantId: widget.applicant?.id,
          firstName: _firstName.text,
          lastName: _lastName.text,
          middleName: _middleName.text,
          educationLevel: _level,
          gradeLevel: _gradeLevel.text,
          programId: _programId,
          guardianName: _guardianName.text,
          guardianPhone: _guardianPhone.text,
          guardianEmail: _guardianEmail.text,
          source: _source.text,
          notes: _notes.text,
        );
    if (!mounted) return;
    setState(() => _working = false);
    if (saved == null) return;

    // The reference is read out to the family while they are still on
    // the phone, so it is said rather than filed.
    _say(saved.referenceNumber == null
        ? 'Saved.'
        : 'Saved as ${saved.referenceNumber}. Give the family that reference.');
    if (widget.applicant == null) Navigator.of(context).pop();
  }

  Future<void> _moveTo(Applicant applicant, AdmissionStage stage) async {
    DateTime? examDate;
    double? score;
    double? maxScore;
    double? fee;
    String? reference;

    // The step and its evidence are collected together, because they are
    // one act: a family is not at "exam taken" without a score, and not
    // at "reserved" without a payment.
    if (stage == AdmissionStage.examScheduled) {
      examDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now().subtract(const Duration(days: 365)),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        helpText: 'When is the entrance exam?',
      );
      if (examDate == null) return;
    } else if (stage == AdmissionStage.examTaken) {
      final result = await _askForExamResult();
      if (result == null) return;
      score = result.$1;
      maxScore = result.$2;
    } else if (stage == AdmissionStage.reserved) {
      final result = await _askForReservation();
      if (result == null) return;
      fee = result.$1;
      reference = result.$2;
    }

    if (!mounted) return;
    setState(() => _working = true);
    final ok = await ref.read(admissionsActionControllerProvider.notifier).advance(
          applicant: applicant,
          stage: stage,
          examScheduledFor: examDate,
          examScore: score,
          examMaxScore: maxScore,
          reservationFee: fee,
          reservationReference: reference,
        );
    if (!mounted) return;
    setState(() => _working = false);
    if (ok) _say('Moved to ${stage.displayLabel}.');
  }

  Future<(double, double)?> _askForExamResult() async {
    final scoreController = TextEditingController();
    final maxController = TextEditingController(text: '100');

    return showDialog<(double, double)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Entrance exam result'),
        content: Row(children: [
          Expanded(
            child: TextField(
              controller: scoreController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Score'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: maxController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Out of'),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final score = double.tryParse(scoreController.text.trim());
              final max = double.tryParse(maxController.text.trim());
              if (score == null || max == null) return;
              Navigator.of(dialogContext).pop((score, max));
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  Future<(double, String)?> _askForReservation() async {
    final amountController = TextEditingController();
    final referenceController = TextEditingController();

    return showDialog<(double, String)>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reservation fee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount paid'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: referenceController,
              decoration: const InputDecoration(
                labelText: 'Receipt or reference (optional)',
              ),
            ),
            const SizedBox(height: 8),
            // Said here because it is the reason this field is on this
            // screen at all: the money follows the family onto their
            // student record instead of being asked for twice.
            const Text(
              'This is credited against their fees when they enrol.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null) return;
              Navigator.of(dialogContext).pop((amount, referenceController.text.trim()));
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  Future<void> _enrol(Applicant applicant) async {
    final sectionController = TextEditingController();
    DateTime? birthDate;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Enrol ${applicant.fullName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This creates their student record. It happens once -- there '
                'is no second student record for the same child.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(labelText: 'Section'),
              ),
              const SizedBox(height: 12),
              // Not asked for at enquiry -- nobody reads a birthday down
              // the phone -- but a student record cannot be issued an ID
              // card without one.
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: DateTime(DateTime.now().year - 12),
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                    helpText: 'Date of birth',
                  );
                  if (picked != null) setDialogState(() => birthDate = picked);
                },
                icon: const Icon(Icons.cake_outlined),
                label: Text(birthDate == null
                    ? 'Date of birth'
                    : formatAdmissionDate(birthDate!)),
              ),
              if (applicant.reservationFeePaid > 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Their reservation of '
                  '${applicant.reservationFeePaid.toStringAsFixed(2)} is carried '
                  'onto the student record as a credit.',
                  style: const TextStyle(fontSize: 12),
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
              child: const Text('Enrol'),
            ),
          ],
        ),
      ),
    );

    if (proceed != true || !mounted) return;
    if (birthDate == null) {
      _say('A date of birth is needed to create the student record.');
      return;
    }

    setState(() => _working = true);
    final enrolled = await ref.read(admissionsActionControllerProvider.notifier).enrol(
          applicant: applicant,
          section: sectionController.text,
          birthDate: birthDate!,
        );
    if (!mounted) return;
    setState(() => _working = false);
    if (enrolled == null) return;

    _say(enrolled.openingCredit > 0
        ? 'Enrolled as ${enrolled.studentNumber}, with '
            '${enrolled.openingCredit.toStringAsFixed(2)} already paid credited '
            'to their account.'
        : 'Enrolled as ${enrolled.studentNumber}.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final applicant = _current;
    final programs = ref.watch(programsStreamProvider).valueOrNull ?? const <Program>[];

    ref.listen(admissionsActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) _say(error.toString());
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(applicant == null ? 'New enquiry' : applicant.fullName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_working) const LinearProgressIndicator(),
          if (applicant != null) ...[
            _StageCard(applicant: applicant),
            const SizedBox(height: 16),
          ],

          Text('The applicant', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _firstName,
                decoration: const InputDecoration(labelText: 'First name'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lastName,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _middleName,
            decoration: const InputDecoration(labelText: 'Middle name (optional)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<EducationLevel>(
            initialValue: _level,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Division'),
            items: [
              for (final level in EducationLevel.values)
                DropdownMenuItem(value: level, child: Text(level.displayLabel)),
            ],
            onChanged: (value) => setState(() {
              _level = value ?? _level;
              // A strand belongs to a division. Keeping the old one
              // after a change would enrol a Senior High applicant onto
              // a college program, which the server refuses -- but the
              // refusal would arrive at the end of a filled-in form.
              _programId = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _gradeLevel,
            decoration: const InputDecoration(
              labelText: 'Applying into',
              hintText: 'Grade 7, 1st Year',
            ),
          ),
          if (_level.usesProgramCatalogue) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _programId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _level.programLabel),
              items: [
                for (final program in programs.where((p) => p.educationLevel == _level))
                  DropdownMenuItem(value: program.id, child: Text(program.name)),
              ],
              onChanged: (value) => setState(() => _programId = value),
            ),
          ],

          const SizedBox(height: 20),
          Text('Who to ring', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _guardianName,
            decoration: const InputDecoration(labelText: 'Parent or guardian'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _guardianPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Mobile number'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _guardianEmail,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email (optional)'),
          ),
          const SizedBox(height: 12),
          // The single most useful field on this record for a school
          // deciding where next year's advertising goes, and the one
          // nobody records anywhere today.
          ComboField(
            controller: _source,
            label: 'How did they hear about us?',
            suggestions: const [
              'Walk-in',
              'Referral from a parent',
              'Facebook',
              'Alumni family',
              'Barangay flyer',
              'Sibling already here',
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),

          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _working ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(applicant == null ? 'Take down the enquiry' : 'Save changes'),
          ),

          if (applicant != null) ...[
            const SizedBox(height: 24),
            Text('Move them on', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (applicant.hasEnrolled)
              const Text(
                'They are enrolled. There is a student record behind this '
                'enquiry now, and it is the record that carries on from here.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final stage in nextStagesFrom(applicant.stage))
                    OutlinedButton(
                      onPressed: _working ? null : () => _moveTo(applicant, stage),
                      child: Text(stage.displayLabel),
                    ),
                  // Enrolment is not a stage anybody sets: it creates a
                  // student record, so it has its own button and its own
                  // callable.
                  if (applicant.stage == AdmissionStage.offered ||
                      applicant.stage == AdmissionStage.reserved)
                    FilledButton.icon(
                      onPressed: _working ? null : () => _enrol(applicant),
                      icon: const Icon(Icons.how_to_reg_outlined),
                      label: const Text('Enrol'),
                    ),
                ],
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final Applicant applicant;
  const _StageCard({required this.applicant});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = applicant.daysInStage(DateTime.now());

    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(applicant.referenceNumber,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            Text(applicant.stage.displayLabel,
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            Text(
              days == 0 ? 'Moved here today' : 'Here for $days day${days == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
            if (applicant.examScheduledFor != null)
              Text('Exam ${formatAdmissionDate(applicant.examScheduledFor!)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
            if (applicant.examPercentage != null)
              Text(
                'Entrance exam ${applicant.examScore!.toStringAsFixed(0)} of '
                '${applicant.examMaxScore!.toStringAsFixed(0)} '
                '(${applicant.examPercentage}%)',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
            if (applicant.reservationFeePaid > 0)
              Text(
                'Reservation paid ${applicant.reservationFeePaid.toStringAsFixed(2)}'
                '${applicant.reservationReference == null ? '' : ' · ${applicant.reservationReference}'}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
              ),
          ],
        ),
      ),
    );
  }
}
