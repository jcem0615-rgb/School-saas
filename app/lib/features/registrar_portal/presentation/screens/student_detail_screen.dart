import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
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

  @override
  Widget build(BuildContext context) {
    final s = widget.student;

    return Scaffold(
      appBar: AppBar(title: Text(s.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.studentNumber, style: Theme.of(context).textTheme.titleMedium),
          Text('Balance: ${_currencyFormat.format(s.balance)}', style: Theme.of(context).textTheme.bodyMedium),
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
          TextField(
            controller: _gradeController,
            decoration: const InputDecoration(labelText: 'Grade Level', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sectionController,
            decoration: const InputDecoration(labelText: 'Section', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<StudentStatus>(
            isExpanded: true,
            value: _status,
            decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
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
