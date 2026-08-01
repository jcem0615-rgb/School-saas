import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/education_level.dart';
import '../../../admin_portal/domain/entities/program.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show programsStreamProvider;
import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../domain/entities/student_summary.dart';
import '../controllers/registrar_controller.dart';
import 'student_detail_screen.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String _query = '';
  EducationLevel? _divisionFilter;

  @override
  Widget build(BuildContext context) {
    final studentsAsync = ref.watch(studentsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Records'),
        actions: [
          IconButton(
            icon: const Icon(Icons.import_export),
            tooltip: 'Export / Import',
            onPressed: _showTransfer,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRegisterSheet(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Register Student'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search by name or student number...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All Divisions'),
                    selected: _divisionFilter == null,
                    onSelected: (_) => setState(() => _divisionFilter = null),
                  ),
                  const SizedBox(width: 8),
                  ...EducationLevel.values.map((level) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(level.displayLabel),
                          selected: _divisionFilter == level,
                          onSelected: (_) => setState(() => _divisionFilter = level),
                        ),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: studentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Failed to load students: $err')),
              data: (students) {
                final filtered = students.where((s) {
                  final matchesQuery = _query.isEmpty ||
                      s.fullName.toLowerCase().contains(_query) ||
                      s.studentNumber.toLowerCase().contains(_query);
                  final matchesDivision = _divisionFilter == null || s.educationLevel == _divisionFilter;
                  return matchesQuery && matchesDivision;
                }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No students found.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final s = filtered[index];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: s.photoUrl != null ? NetworkImage(s.photoUrl!) : null,
                          child: s.photoUrl == null ? const Icon(Icons.school_outlined) : null,
                        ),
                        title: Text(s.fullName),
                        subtitle: Text(
                          s.isCollege
                              ? '${s.studentNumber} · ${s.educationLevel.displayLabel} · ${s.programName ?? "No program"}'
                              : '${s.studentNumber} · ${s.educationLevel.displayLabel} · ${s.gradeLevel} - ${s.section}',
                        ),
                        trailing: s.status != StudentStatus.enrolled
                            ? Chip(label: Text(s.status.displayLabel), visualDensity: VisualDensity.compact)
                            : null,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => StudentDetailScreen(student: s))),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Export is unrestricted; import deliberately is not offered here.
  ///
  /// Student numbers come from a server-side counter at registration, and
  /// firestore.rules rejects client writes to `studentNumber`, `userId`
  /// and `balance`. A CSV import that appeared to create students would
  /// either bypass those rules or silently drop the fields, so the honest
  /// option is export-only with the reason stated in the sheet.
  void _showTransfer() {
    final students = ref.read(studentsStreamProvider).valueOrNull ?? const <StudentSummary>[];
    showExportImportSheet(
      context: context,
      label: 'Students',
      headers: const [
        'Student Number',
        'Last Name',
        'First Name',
        'Middle Name',
        'Division',
        'Grade Level',
        'Section',
        'Program',
        'Status',
        'Balance',
      ],
      rows: () => students
          .map((s) => [
                s.studentNumber,
                s.lastName,
                s.firstName,
                s.middleName ?? '',
                s.educationLevel.displayLabel,
                s.gradeLevel,
                s.section,
                s.programName ?? '',
                s.status.displayLabel,
                s.balance.toStringAsFixed(2),
              ])
          .toList(),
    );
  }

  Future<void> _showRegisterSheet(BuildContext context, WidgetRef ref) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final middleNameController = TextEditingController();
    final gradeController = TextEditingController();
    final sectionController = TextEditingController();
    final guardianNameController = TextEditingController();
    final guardianPhoneController = TextEditingController();
    EducationLevel? educationLevel;
    Program? selectedProgram;

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
                Text('Register Student', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 16),
                // The explicit ask: every student must declare which
                // division they belong to at sign-up. Required -- no
                // default is pre-selected, so a Registrar can't
                // accidentally register someone into the wrong division.
                DropdownButtonFormField<EducationLevel>(
                  isExpanded: true,
                  value: educationLevel,
                  decoration: const InputDecoration(
                    labelText: 'Division (Elementary / High School / College)',
                    border: OutlineInputBorder(),
                  ),
                  items: EducationLevel.values
                      .map((level) => DropdownMenuItem(value: level, child: Text(level.displayLabel)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    educationLevel = v;
                    selectedProgram = null; // clear any stale selection when switching divisions
                  }),
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
                  controller: middleNameController,
                  decoration: const InputDecoration(labelText: 'Middle Name (optional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                // Suggest what the school already uses, but still allow a
                // brand-new grade level or section to be typed in.
                Consumer(
                  builder: (context, ref, _) {
                    final existing =
                        ref.watch(studentsStreamProvider).valueOrNull ?? const <StudentSummary>[];
                    // Only offer levels from the same division: a college
                    // year level is not a useful suggestion for a Grade 4.
                    final sameDivision =
                        existing.where((e) => e.educationLevel == educationLevel);
                    return Column(
                      children: [
                        ComboField(
                          controller: gradeController,
                          label: educationLevel == EducationLevel.college
                              ? 'Year Level (e.g. 1st Year)'
                              : 'Grade Level',
                          suggestions: sameDivision.map((e) => e.gradeLevel).toList(),
                        ),
                        const SizedBox(height: 12),
                        ComboField(
                          controller: sectionController,
                          label: 'Section / Block',
                          suggestions: sameDivision.map((e) => e.section).toList(),
                        ),
                      ],
                    );
                  },
                ),
                // Course selection only ever appears for College -- this
                // is the "include the courses if it is college" piece.
                if (educationLevel == EducationLevel.college) ...[
                  const SizedBox(height: 12),
                  Consumer(
                    builder: (context, ref, _) {
                      final programsAsync = ref.watch(programsStreamProvider);
                      return programsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (err, _) => Text('Failed to load programs: $err'),
                        data: (programs) {
                          if (programs.isEmpty) {
                            return const Text(
                              'No college programs configured yet. Ask an Admin to add one under College Programs first.',
                              style: TextStyle(color: Colors.red),
                            );
                          }
                          return DropdownButtonFormField<Program>(
                            isExpanded: true,
                            value: selectedProgram,
                            decoration: const InputDecoration(
                              labelText: 'Program / Course',
                              border: OutlineInputBorder(),
                            ),
                            items: programs
                                .map((p) => DropdownMenuItem(value: p, child: Text('${p.name} (${p.code})')))
                                .toList(),
                            onChanged: (v) => setState(() => selectedProgram = v),
                          );
                        },
                      );
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Text('Guardian Contact', style: Theme.of(sheetContext).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: guardianNameController,
                  decoration: const InputDecoration(labelText: 'Guardian Name', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: guardianPhoneController,
                  decoration: const InputDecoration(labelText: 'Guardian Phone', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    if (educationLevel == null) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(content: Text('Please select a division.')),
                      );
                      return;
                    }
                    final navigator = Navigator.of(sheetContext);
                    final guardians = guardianNameController.text.trim().isEmpty
                        ? <GuardianContact>[]
                        : [
                            GuardianContact(
                              name: guardianNameController.text,
                              relationship: 'Guardian',
                              phone: guardianPhoneController.text,
                            ),
                          ];
                    final outcome = await ref.read(registrarActionControllerProvider.notifier).registerStudent(
                          firstName: firstNameController.text,
                          lastName: lastNameController.text,
                          middleName: middleNameController.text,
                          educationLevel: educationLevel!,
                          gradeLevel: gradeController.text,
                          section: sectionController.text,
                          programId: selectedProgram?.id,
                          guardianContacts: guardians,
                        );
                    if (outcome != null) {
                      navigator.pop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Registered as ${outcome.studentNumber}')),
                        );
                      }
                    } else {
                      final state = ref.read(registrarActionControllerProvider);
                      if (state case AsyncError(:final error)) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text(error.toString())));
                      }
                    }
                  },
                  child: const Text('Register'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
