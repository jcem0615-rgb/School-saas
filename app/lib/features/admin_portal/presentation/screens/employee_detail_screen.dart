import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/user_roles.dart';
import '../../domain/entities/employee_summary.dart';
import '../controllers/admin_controller.dart';

final _dateFormat = DateFormat.yMMMd();

class EmployeeDetailScreen extends ConsumerStatefulWidget {
  final EmployeeSummary employee;
  const EmployeeDetailScreen({super.key, required this.employee});

  @override
  ConsumerState<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends ConsumerState<EmployeeDetailScreen> {
  late final TextEditingController _departmentController;
  late final TextEditingController _positionController;
  late final TextEditingController _assignedDepartmentController;
  late EducationLevel? _assignedDivision;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _departmentController = TextEditingController(text: widget.employee.employeeInfo?.department ?? '');
    _positionController = TextEditingController(text: widget.employee.employeeInfo?.position ?? '');
    _assignedDepartmentController =
        TextEditingController(text: widget.employee.employeeInfo?.assignedDepartment ?? '');
    _assignedDivision = widget.employee.employeeInfo?.assignedDivision;
  }

  @override
  void dispose() {
    _departmentController.dispose();
    _positionController.dispose();
    _assignedDepartmentController.dispose();
    super.dispose();
  }

  Future<void> _saveInfo() async {
    setState(() => _saving = true);
    final success = await ref.read(adminActionControllerProvider.notifier).updateEmployeeInfo(
          uid: widget.employee.uid,
          employeeInfo: EmployeeInfo(
            department: _departmentController.text,
            position: _positionController.text,
            dateHired: widget.employee.employeeInfo?.dateHired ?? DateTime.now(),
            assignedDivision: _assignedDivision,
            assignedDepartment:
                _assignedDepartmentController.text.trim().isEmpty ? null : _assignedDepartmentController.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Employee info updated.' : 'Failed to update employee info.')),
    );
  }

  Future<void> _toggleStatus() async {
    final activate = widget.employee.status == UserAccountStatus.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(activate ? 'Activate this account?' : 'Suspend this account?'),
        content: Text(
          activate
              ? '${widget.employee.fullName} will regain access immediately.'
              : '${widget.employee.fullName} will immediately lose access to the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: activate ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(activate ? 'Activate' : 'Suspend'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await ref
        .read(adminActionControllerProvider.notifier)
        .setUserStatus(uid: widget.employee.uid, active: activate);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success ? 'Status updated.' : 'Failed to update status.')),
    );
  }

  Future<void> _resetPassword() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset password?'),
        content: Text('${widget.employee.fullName} will be required to set a new password on next login.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final link = await ref.read(adminActionControllerProvider.notifier).resetUserPassword(widget.employee.uid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(link != null ? 'Password reset initiated.' : 'Failed to reset password.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.employee;
    final isSuspended = e.status == UserAccountStatus.suspended;

    return Scaffold(
      appBar: AppBar(title: Text(e.fullName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: e.photoUrl != null ? NetworkImage(e.photoUrl!) : null,
                child: e.photoUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.fullName, style: Theme.of(context).textTheme.titleLarge),
                    Text('${e.role.displayName} · ${e.email}'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('HR Details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _departmentController,
            decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _positionController,
            decoration: const InputDecoration(labelText: 'Position', border: OutlineInputBorder()),
          ),
          if (e.employeeInfo != null) ...[
            const SizedBox(height: 8),
            Text('Hired: ${_dateFormat.format(e.employeeInfo!.dateHired)}', style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 16),
          Text('Data Access Scope', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Leave unrestricted for normal cross-division access. Restricting scopes this '
            'employee to only students in the assigned division (see docs/15-divisions-and-programs.md).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<EducationLevel?>(
            value: _assignedDivision,
            decoration: const InputDecoration(labelText: 'Assigned Division', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem<EducationLevel?>(value: null, child: Text('Unrestricted (all divisions)')),
              ...EducationLevel.values.map((l) => DropdownMenuItem(value: l, child: Text(l.displayLabel))),
            ],
            onChanged: (v) => setState(() => _assignedDivision = v),
          ),
          if (_assignedDivision == EducationLevel.college) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _assignedDepartmentController,
              decoration: const InputDecoration(
                labelText: 'Assigned College Department (optional)',
                hintText: 'Leave blank to scope to all of College',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _saving ? null : _saveInfo,
            child: _saving ? const CircularProgressIndicator() : const Text('Save HR Details'),
          ),
          const Divider(height: 40),
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _toggleStatus,
            icon: Icon(isSuspended ? Icons.play_circle_outline : Icons.block),
            label: Text(isSuspended ? 'Activate Account' : 'Suspend Account'),
            style: isSuspended ? null : FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _resetPassword,
            icon: const Icon(Icons.lock_reset),
            label: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }
}
