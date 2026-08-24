import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/education_level.dart';
import '../../../admin_portal/domain/entities/program.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart' show programsStreamProvider;
import '../../../../core/data_transfer/export_import_sheet.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../domain/entities/student_summary.dart';
import '../import/student_import.dart';
import '../../domain/usecases/student_usecases.dart';
import '../controllers/registrar_controller.dart';
import 'student_detail_screen.dart';
import '../../../../core/widgets/field_tile.dart';

class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String _query = '';
  bool _loadingTransfer = false;

  /// Load more widens the query rather than appending a page, so the list
  /// stays one live stream. See [pagedStudentsStreamProvider].
  void _loadMore() {
    final pageSize = ref.read(studentPageSizeProvider);
    ref.read(studentPageLimitProvider.notifier).update((n) => n + pageSize);
  }

  /// Changing the division changes the query, so the page count starts
  /// over. Without this, switching to Senior High after loading sixty
  /// Elementary records would ask Firestore for sixty Senior High ones.
  void _setDivision(EducationLevel? level) {
    ref.read(studentDivisionFilterProvider.notifier).state = level;
    ref.read(studentPageLimitProvider.notifier).state = ref.read(studentPageSizeProvider);
  }

  @override
  Widget build(BuildContext context) {
    final divisionFilter = ref.watch(studentDivisionFilterProvider);
    final limit = ref.watch(studentPageLimitProvider);

    // Typing switches the screen off the paged query and onto the whole
    // roster. Firestore cannot match a substring, so "cruz" can only be
    // found by looking at every record -- and a search that quietly only
    // covered the page you had already scrolled to would be worse than no
    // search at all. Browsing is paged; searching is a deliberate,
    // occasional full read.
    final searching = _query.isNotEmpty;
    final studentsAsync =
        searching ? ref.watch(studentsStreamProvider) : ref.watch(pagedStudentsStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Records'),
        actions: [
          IconButton(
            icon: _loadingTransfer
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.import_export),
            tooltip: 'Export / Import',
            onPressed: _loadingTransfer ? null : _showTransfer,
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
                    selected: divisionFilter == null,
                    onSelected: (_) => _setDivision(null),
                  ),
                  const SizedBox(width: 8),
                  ...EducationLevel.values.map((level) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(level.displayLabel),
                          selected: divisionFilter == level,
                          onSelected: (_) => _setDivision(level),
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
                // While browsing, both filters are already in the query --
                // re-applying them here would be a no-op. While searching,
                // the stream is the unbounded roster and neither has been
                // applied yet.
                final filtered = !searching
                    ? students
                    : students.where((s) {
                        final matchesQuery = s.fullName.toLowerCase().contains(_query) ||
                            s.studentNumber.toLowerCase().contains(_query);
                        final matchesDivision =
                            divisionFilter == null || s.educationLevel == divisionFilter;
                        return matchesQuery && matchesDivision;
                      }).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No students found.'));
                }
                // A full page came back, so there is probably another one.
                // "Probably" is as good as it gets without a second count
                // query, and offering a Load more that turns out to add
                // nothing is cheaper than hiding one that would have.
                final hasMore = !searching && students.length >= limit;
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  // The extra row is the footer: the count, and Load more
                  // when there is more. Inside the list rather than under
                  // it so it scrolls with the records instead of pinning a
                  // bar across the bottom of a phone screen.
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == filtered.length) {
                      return _ListFooter(
                        count: filtered.length,
                        searching: searching,
                        hasMore: hasMore,
                        onLoadMore: _loadMore,
                      );
                    }
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
                              : '${s.studentNumber} · ${s.educationLevel.displayLabel} · ${s.classLabel}',
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

  /// Moves the roster in and out as a spreadsheet.
  ///
  /// Import used to be refused here, and the reason given was that
  /// `studentNumber`, `userId` and `balance` are server-owned and
  /// firestore.rules rejects client writes to them. That reasoning was
  /// right about the fields and wrong about the conclusion: the import
  /// does not have to write those fields, because it does not have to
  /// write documents at all. Every row goes through `registerStudent`,
  /// the same callable the New Student form uses, which allocates the
  /// student number from the server-side counter and initialises the
  /// balance. Three hundred rows take the same path one typed student
  /// does, and nothing is bypassed.
  ///
  /// The export reads every student explicitly rather than exporting
  /// whatever the paged list happens to be holding -- a file that
  /// silently stopped at the twenty rows on screen is the exact failure
  /// paging invites, and the kind noticed only after the file has gone to
  /// the division office.
  Future<void> _showTransfer() async {
    setState(() => _loadingTransfer = true);

    // Held open for as long as the sheet is: the row parser needs the
    // catalogue to turn "BS Computer Science" into a programId, and it
    // runs when the user picks a file, long after this method returns.
    final catalogue = ref.listenManual(programsStreamProvider, (_, __) {});

    final List<StudentSummary> students;
    final List<Program> programs;
    try {
      students = await FetchAllStudentsUseCase(ref.read(registrarRepositoryProvider))();
      programs = await ref.read(programsStreamProvider.future);
    } catch (err) {
      catalogue.close();
      if (mounted) {
        setState(() => _loadingTransfer = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load the roster: $err')),
        );
      }
      return;
    }
    if (!mounted) {
      catalogue.close();
      return;
    }
    setState(() => _loadingTransfer = false);

    // A file listing the same student twice is a copy-paste accident, not
    // twins. Caught per file rather than per row, so it has to live out
    // here where the parser can close over it.
    final seen = <String>{};

    await showExportImportSheet(
      context: context,
      label: 'Students',
      // Everything a record has, including the three fields the server
      // owns. The importer ignores them by name, so a file exported here
      // can be imported straight back into another school.
      headers: const [
        'Student Number',
        'Last Name',
        'First Name',
        'Middle Name',
        'Division',
        'Grade Level',
        'Section',
        'Program',
        'Birthday',
        'Guardian Name',
        'Guardian Phone',
        'Status',
        'Balance',
      ],
      importHeaders: const [
        'Last Name',
        'First Name',
        'Middle Name',
        'Division',
        'Grade Level',
        'Section',
        'Program',
        'Birthday',
        'Guardian Name',
        'Guardian Phone',
      ],
      importNote:
          'Student numbers are assigned by the system as each row is '
          'registered, and every imported student starts enrolled with a '
          'zero balance — those three columns are ignored if your file has '
          'them. Division must be Elementary, Junior High School, Senior '
          'High School or College. Birthday is optional: leave the cell '
          'empty if you do not have it, or write it as 2012-03-07.',
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
                s.birthDate == null ? '' : StudentImport.isoDate(s.birthDate!),
                s.guardianContacts.firstOrNull?.name ?? '',
                s.guardianContacts.firstOrNull?.phone ?? '',
                s.status.displayLabel,
                s.balance.toStringAsFixed(2),
              ])
          .toList(),
      parseRow: (row, rowNumber) => StudentImport.parseRow(
        row: row,
        rowNumber: rowNumber,
        programs: programs,
        existing: students,
        seen: seen,
      ),
      onImport: (records) async {
        // One at a time, counting what actually lands. registerStudent is
        // a callable per row, so a failure partway through has already
        // created the students before it -- reporting the true count is
        // the difference between "47 of 300 imported, fix and re-run" and
        // a registrar importing the whole file again on top.
        final notifier = ref.read(registrarActionControllerProvider.notifier);
        var created = 0;
        for (final r in records.cast<StudentImportRow>()) {
          final outcome = await notifier.registerStudent(
            firstName: r.firstName,
            lastName: r.lastName,
            middleName: r.middleName,
            educationLevel: r.educationLevel,
            gradeLevel: r.gradeLevel,
            section: r.section,
            programId: r.programId,
            birthDate: r.birthDate,
            guardianContacts: r.guardianContacts,
          );
          if (outcome != null) created++;
        }
        return created;
      },
    );

    catalogue.close();
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
    DateTime? birthDate;

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
                    labelText: 'Division',
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
                  decoration: const InputDecoration(labelText: 'First Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: lastNameController,
                  decoration: const InputDecoration(labelText: 'Last Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: middleNameController,
                  decoration: const InputDecoration(labelText: 'Middle Name (optional)'),
                ),
                const SizedBox(height: 12),
                // Suggest what the school already uses, but still allow a
                // brand-new grade level or section to be typed in.
                Consumer(
                  builder: (context, ref, _) {
                    final existing =
                        ref.watch(pagedStudentsStreamProvider).valueOrNull ?? const <StudentSummary>[];
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
                // The catalogue field appears only for the two divisions
                // that have one: a strand for Senior High, a degree
                // program for College. Elementary and Junior High get no
                // field at all -- their grade level and section already
                // say everything the record needs.
                if (educationLevel?.usesProgramCatalogue ?? false) ...[
                  const SizedBox(height: 12),
                  Consumer(
                    builder: (context, ref, _) {
                      final programsAsync = ref.watch(programsStreamProvider);
                      return programsAsync.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (err, _) => Text('Failed to load the catalogue: $err'),
                        data: (all) {
                          // A college program is not a valid choice for a
                          // Senior High student and vice versa, so the
                          // list is filtered to the division rather than
                          // relying on the registrar to pick correctly.
                          final programs = all
                              .where((p) => p.educationLevel == educationLevel)
                              .toList();
                          final label = educationLevel!.programLabel;
                          if (programs.isEmpty) {
                            return Text(
                              'No ${label.toLowerCase()} options configured yet. Ask an '
                              'Admin to add one under Strands & Programs first.',
                              style: const TextStyle(color: Colors.red),
                            );
                          }
                          return DropdownButtonFormField<Program>(
                            isExpanded: true,
                            value: programs.contains(selectedProgram) ? selectedProgram : null,
                            decoration: InputDecoration(
                              labelText: label,
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
                const SizedBox(height: 12),
                // Required: it is printed on the ID card, and chasing it
                // down after the fact is what left records without one.
                FieldTile(
                  icon: Icons.cake_outlined,
                  label: 'Birthday (required)',
                  value: birthDate == null
                      ? null
                      : DateFormat.yMMMd().format(birthDate!),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: sheetContext,
                      firstDate: DateTime(now.year - 80),
                      lastDate: now,
                      initialDate: birthDate ?? DateTime(now.year - 12),
                    );
                    if (picked != null) setState(() => birthDate = picked);
                  },
                ),
                const SizedBox(height: 16),
                Text('Guardian Contact', style: Theme.of(sheetContext).textTheme.labelLarge),
                const SizedBox(height: 8),
                TextField(
                  controller: guardianNameController,
                  decoration: const InputDecoration(labelText: 'Guardian Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: guardianPhoneController,
                  decoration: const InputDecoration(labelText: 'Guardian Phone'),
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
                          birthDate: birthDate,
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

/// The row under the last student: what you are looking at, and how to
/// see more of it.
class _ListFooter extends StatelessWidget {
  final int count;
  final bool searching;
  final bool hasMore;
  final VoidCallback onLoadMore;

  const _ListFooter({
    required this.count,
    required this.searching,
    required this.hasMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final label = searching
        ? '$count matching ${count == 1 ? "student" : "students"}'
        : hasMore
            ? 'Showing $count students'
            : 'Showing all $count ${count == 1 ? "student" : "students"}';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      child: Column(
        children: [
          if (hasMore)
            OutlinedButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more'),
            ),
          if (hasMore) const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
