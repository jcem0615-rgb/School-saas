import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../../core/constants/user_roles.dart';
import '../../domain/entities/employee_summary.dart';
import '../../domain/usecases/employee_usecases.dart';
import '../controllers/admin_controller.dart';
import 'employee_detail_screen.dart';

class EmployeeListScreen extends ConsumerWidget {
  const EmployeeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final employeesAsync = ref.watch(employeesStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Employee Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New Employee'),
      ),
      body: employeesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Failed to load employees: $err')),
        data: (employees) {
          if (employees.isEmpty) {
            return const Center(child: Text('No employees yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: employees.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final e = employees[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: e.photoUrl != null ? NetworkImage(e.photoUrl!) : null,
                    child: e.photoUrl == null
                        ? Text(e.firstName.isNotEmpty ? e.firstName[0] : '?')
                        : null,
                  ),
                  title: Text(e.fullName),
                  subtitle: Text('${e.role.displayName}${e.employeeInfo != null ? ' · ${e.employeeInfo!.position}' : ''}'),
                  trailing: e.status == UserAccountStatus.suspended
                      ? const Chip(label: Text('Suspended'), visualDensity: VisualDensity.compact)
                      : null,
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => EmployeeDetailScreen(employee: e))),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showCreateSheet(BuildContext context, WidgetRef ref) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final emailController = TextEditingController();
    final departmentController = TextEditingController();
    final positionController = TextEditingController();
    final assignedDepartmentController = TextEditingController();
    UserRole role = adminProvisionableRoles.first;
    DateTime dateHired = DateTime.now();
    EducationLevel? assignedDivision;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('New Employee', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<UserRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                  items: adminProvisionableRoles
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.displayName)))
                      .toList(),
                  onChanged: (v) => setState(() => role = v ?? role),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: firstNameController,
                  decoration: const InputDecoration(labelText: 'First Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(labelText: 'Last Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: departmentController,
                  decoration: const InputDecoration(labelText: 'Department (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: positionController,
                  decoration: const InputDecoration(labelText: 'Position (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<EducationLevel?>(
                  initialValue: assignedDivision,
                  decoration: const InputDecoration(
                    labelText: 'Data Access Scope (optional)',
                    helperText: 'Leave unset for normal cross-division access. Set to restrict '
                        'this staff member to only their assigned division.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<EducationLevel?>(value: null, child: Text('Unrestricted (all divisions)')),
                    ...EducationLevel.values.map((l) => DropdownMenuItem(value: l, child: Text(l.displayLabel))),
                  ],
                  onChanged: (v) => setState(() => assignedDivision = v),
                ),
                if (assignedDivision == EducationLevel.college) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: assignedDepartmentController,
                    decoration: const InputDecoration(
                      labelText: 'Assigned College Department (optional)',
                      hintText: 'e.g. College of Engineering -- leave blank to scope to all of College',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    final navigator = Navigator.of(sheetContext);
                    final controller = ref.read(adminActionControllerProvider.notifier);
                    final hasEmployeeInfo = departmentController.text.trim().isNotEmpty ||
                        positionController.text.trim().isNotEmpty ||
                        assignedDivision != null;
                    await controller.createEmployee(
                      role: role,
                      firstName: firstNameController.text,
                      lastName: lastNameController.text,
                      email: emailController.text,
                      employeeInfo: !hasEmployeeInfo
                          ? null
                          : EmployeeInfo(
                              department: departmentController.text,
                              position: positionController.text,
                              dateHired: dateHired,
                              assignedDivision: assignedDivision,
                              assignedDepartment: assignedDepartmentController.text.trim().isEmpty
                                  ? null
                                  : assignedDepartmentController.text.trim(),
                            ),
                    );
                    final resultState = ref.read(adminActionControllerProvider);
                    if (resultState case AsyncData(value: final outcome?)) {
                      navigator.pop();
                      if (sheetContext.mounted) {
                        showDialog<void>(
                          context: sheetContext,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('Employee Created'),
                            content: SelectableText(
                              'Temporary password:\n${outcome.tempPassword}\n\nShare this securely -- it will not be shown again.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: const Text('Done'),
                              ),
                            ],
                          ),
                        );
                      }
                      ref.read(adminActionControllerProvider.notifier).reset();
                    } else if (resultState case AsyncError(:final error)) {
                      ScaffoldMessenger.of(sheetContext)
                          .showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  },
                  child: const Text('Create Employee'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
