import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:file_picker/file_picker.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/storage/upload_providers.dart';
import '../../../../core/storage/upload_repository.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../payments/presentation/screens/payment_history_screen.dart';
import '../../../payments/presentation/screens/record_payment_screen.dart';
import '../../../qr_attendance/presentation/screens/attendance_history_screen.dart';
import '../../domain/entities/student_summary.dart';
import '../controllers/registrar_controller.dart';

final _currencyFormat = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

/// The Registrar's per-student hub: this is where Student Records, Student
/// History (via the attendance/payment links), Payment Collection,
/// Balances, and Student Portal account provisioning all meet -- rather
/// than scattering these across separate top-level screens, since a
/// Registrar's actual workflow is almost always "pull up this one
/// student, then do several things."
class StudentDetailScreen extends ConsumerStatefulWidget {
  final StudentSummary student;
  const StudentDetailScreen({super.key, required this.student});

  @override
  ConsumerState<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends ConsumerState<StudentDetailScreen> {
  late final TextEditingController _gradeController;
  late final TextEditingController _sectionController;
  late StudentStatus _status;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _gradeController = TextEditingController(text: widget.student.gradeLevel);
    _sectionController = TextEditingController(text: widget.student.section);
    _status = widget.student.status;
  }

  @override
  void dispose() {
    _gradeController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    final success = await ref.read(registrarActionControllerProvider.notifier).updateStudent(
          studentId: widget.student.id,
          firstName: widget.student.firstName,
          lastName: widget.student.lastName,
          gradeLevel: _gradeController.text,
          section: _sectionController.text,
          status: _status,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Student record updated.' : 'Failed to update record.')),
    );
  }

  Future<void> _provisionAccount() async {
    final emailController = TextEditingController();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create Student Portal Account'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(emailController.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (email == null || email.trim().isEmpty || !mounted) return;

    final outcome = await ref.read(registrarActionControllerProvider.notifier).provisionStudentAccount(
          studentId: widget.student.id,
          firstName: widget.student.firstName,
          lastName: widget.student.lastName,
          email: email,
        );
    if (!mounted) return;
    if (outcome != null) {
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Account Created'),
          content: SelectableText(
            'Temporary password:\n${outcome.tempPassword}\n\nShare this securely -- it will not be shown again.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Done')),
          ],
        ),
      );
    } else {
      final state = ref.read(registrarActionControllerProvider);
      if (state case AsyncError(:final error)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  /// Uploads an ID photo for this student.
  ///
  /// Two steps that are kept visibly separate: the bytes go to Storage,
  /// and only if that succeeds does `photoUrl` go onto the record. A
  /// single combined call would report a photo saved when the upload
  /// landed and the write did not, leaving a file nothing points at.
  ///
  /// The photo is what a guard actually checks the card against, so it is
  /// worth having here on the Registrar's own screen rather than waiting
  /// for the student to set one on their profile -- most students are
  /// issued a card before they ever sign in.
  Future<void> _uploadPhoto() async {
    final picked = await FilePicker.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = picked?.files.singleOrNull;
    if (file?.bytes == null) return;

    setState(() => _uploadingPhoto = true);
    final result = await ref.read(uploadRepositoryProvider).upload(
          folder: UploadFolder.studentPhotos,
          fileName: file!.name,
          bytes: file.bytes!,
          contentType: 'image/${file.extension}',
        );
    if (!mounted) return;

    switch (result) {
      case Success<UploadedFile>(:final value):
        final ok = await ref.read(registrarActionControllerProvider.notifier).setStudentPhoto(
              studentId: widget.student.id,
              photoUrl: value.url,
            );
        if (!mounted) return;
        setState(() => _uploadingPhoto = false);
        if (ok) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('Photo saved.')));
        }
      case Error<UploadedFile>(:final failure):
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// Editing a balance is not an ordinary field edit -- it goes through the
  /// setStudentBalance callable, because firestore.rules keeps `balance`
  /// closed to direct client writes so the payment transactions stay its
  /// only other writer. The reason is mandatory and lands in the audit log.
  Future<void> _editBalance(BuildContext context, WidgetRef ref, StudentSummary s) async {
    final amountController = TextEditingController(text: s.balance.toStringAsFixed(2));
    final remarksController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set Balance'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Assessed total for ${s.fullName}. Payments adjust this '
              'automatically -- set it here only when fees are assessed or '
              'an assessment is corrected.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(
                labelText: 'Balance (₱)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: remarksController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. First semester assessment',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final parsed = double.tryParse(amountController.text);
              if (parsed == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter a valid amount.')),
                );
                return;
              }
              final ok = await ref.read(registrarActionControllerProvider.notifier).setStudentBalance(
                    studentId: s.id,
                    balance: parsed,
                    remarks: remarksController.text,
                  );
              if (ok && dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Suggestions come from the school's live records rather than a fixed
    // list, so a section invented this year shows up without a code change.
    final allStudents = ref.watch(studentsStreamProvider).valueOrNull ?? const <StudentSummary>[];

    // Re-read the student from the live list rather than rendering the
    // snapshot this screen was constructed with. Balance in particular is
    // changed from here (and by every payment), and a captured copy shows
    // the old figure until you navigate away and back.
    final s = allStudents.firstWhere(
      (e) => e.id == widget.student.id,
      orElse: () => widget.student,
    );

    // Every other action screen listens to its controller; this one did
    // not, which had two consequences. The controller is autoDispose, so
    // with no listener it could be torn down between `ref.read(...)` and
    // the write completing -- "used after dispose" -- and any failure it
    // reported was invisible, since nothing was watching to show it.
    ref.listen(registrarActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(s.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PhotoHeader(
            student: s,
            uploading: _uploadingPhoto,
            onUpload: _uploadPhoto,
          ),
          const SizedBox(height: 16),
          Text(s.studentNumber, style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Balance: ${_currencyFormat.format(s.balance)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _editBalance(context, ref, s),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.account_tree_outlined, size: 16),
                label: Text(s.educationLevel.displayLabel),
                visualDensity: VisualDensity.compact,
              ),
              if (s.isCollege && s.programName != null)
                Chip(
                  avatar: const Icon(Icons.school_outlined, size: 16),
                  label: Text(s.programName!),
                  visualDensity: VisualDensity.compact,
                ),
              if (s.isCollege && s.department != null)
                Chip(
                  avatar: const Icon(Icons.apartment_outlined, size: 16),
                  label: Text(s.department!),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionChip(
                icon: Icons.payments_outlined,
                label: 'Record Payment',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => RecordPaymentScreen(studentId: s.id, studentName: s.fullName),
                  ),
                ),
              ),
              _ActionChip(
                icon: Icons.receipt_long_outlined,
                label: 'Payment History',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PaymentHistoryScreen(studentId: s.id, studentName: s.fullName),
                  ),
                ),
              ),
              _ActionChip(
                icon: Icons.fact_check_outlined,
                label: 'Attendance History',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttendanceHistoryScreen(personId: s.id, title: '${s.fullName} - Attendance'),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 40),
          Text('Record Details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Grade level and section are free text in this system -- a school
          // can add "Grade 11 - STEM B" mid-year -- so these offer the values
          // already in use without preventing a new one being typed.
          ComboField(
            controller: _gradeController,
            label: 'Grade Level',
            suggestions: allStudents.map((e) => e.gradeLevel).toList(),
          ),
          const SizedBox(height: 12),
          ComboField(
            controller: _sectionController,
            label: 'Section',
            suggestions: allStudents.map((e) => e.section).toList(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<StudentStatus>(
            isExpanded: true,
            value: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: StudentStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.displayLabel)))
                .toList(),
            onChanged: (v) => setState(() => _status = v ?? _status),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _saving ? null : _saveChanges,
            child: _saving ? const CircularProgressIndicator() : const Text('Save Changes'),
          ),
          const Divider(height: 40),
          Text('Student Portal Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (s.hasPortalAccount)
            const Text('This student already has a portal account.')
          else
            FilledButton.icon(
              onPressed: _provisionAccount,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Create Student Portal Account'),
            ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: onTap);
  }
}

/// The student's ID photo, and the way to change it.
///
/// A 3:4 rectangle rather than a circle, because that is the shape it is
/// printed in on the ID card -- a round preview of a square crop is a
/// promise the printed card does not keep. Initials stand in for a
/// missing photo for the same reason they do on the card: a blank grey
/// box reads as a fault, initials read as "no photo yet".
class _PhotoHeader extends StatelessWidget {
  final StudentSummary student;
  final bool uploading;
  final VoidCallback onUpload;

  const _PhotoHeader({
    required this.student,
    required this.uploading,
    required this.onUpload,
  });

  String get _initials {
    final parts = student.fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPhoto = student.photoUrl != null && student.photoUrl!.isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          height: 128,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              color: theme.colorScheme.surfaceContainerHighest,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: hasPhoto
                  ? Image.network(
                      student.photoUrl!,
                      fit: BoxFit.cover,
                      // A photo that will not load must not take the
                      // screen with it -- fall back to the same
                      // placeholder as no photo at all.
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(_initials, style: theme.textTheme.headlineMedium),
                      ),
                    )
                  : Center(
                      child: Text(
                        _initials,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID photo', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Printed on this student\'s ID card and shown on the roster. '
                'A head-and-shoulders shot works best — the card crops to a '
                '3:4 portrait.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: uploading ? null : onUpload,
                icon: uploading
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  uploading
                      ? 'Uploading…'
                      : hasPhoto
                          ? 'Replace photo'
                          : 'Upload photo',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
