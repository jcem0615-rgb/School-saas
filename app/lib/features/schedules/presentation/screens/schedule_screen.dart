import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/user_roles.dart';
import '../../../../core/widgets/combo_field.dart';
import '../../../admin_portal/domain/entities/employee_summary.dart';
import '../../../admin_portal/domain/entities/school_branding.dart';
import '../../../admin_portal/presentation/controllers/admin_controller.dart'
    show brandingProvider, employeesStreamProvider, teacherAssignmentsStreamProvider;
import '../../../auth/presentation/controllers/auth_controller.dart' show authStateProvider;
import '../../../registrar_portal/presentation/controllers/registrar_controller.dart'
    show studentsStreamProvider;
import '../../domain/entities/schedule_block.dart';
import '../controllers/schedule_controller.dart';
import '../documents/timetable_pdf.dart';
import '../widgets/timetable_view.dart';

/// The school's timetable, and the one place it is edited.
///
/// Filtered by section, by teacher or by room rather than showing the
/// whole week at once. A school's week is a few hundred classes and
/// nobody reads it as one list -- the questions are always "what does
/// 10-Rizal do", "when is Ms Cruz free", "is Room 201 taken at ten".
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

enum _Lens { section, teacher, room }

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  _Lens _lens = _Lens.section;
  String? _value;

  List<String> _choicesFor(_Lens lens, List<ScheduleBlock> all, List<dynamic> sections) {
    switch (lens) {
      case _Lens.section:
        // Sections come from the roll as well as the timetable, so a
        // section with students but no classes yet can be picked and
        // given some.
        return {
          ...all.map((b) => b.section.trim()),
          ...sections.map((s) => (s as String).trim()),
        }.where((s) => s.isNotEmpty).toList()
          ..sort();
      case _Lens.teacher:
        return {for (final b in all) b.teacherName.trim()}.where((s) => s.isNotEmpty).toList()
          ..sort();
      case _Lens.room:
        return {for (final b in all) b.room?.trim() ?? ''}.where((s) => s.isNotEmpty).toList()
          ..sort();
    }
  }

  /// The first choice that actually has classes in it, or the first
  /// choice at all. Sections come from the roll as well as from the
  /// timetable, so the alphabetically first one is often one nobody has
  /// timetabled yet.
  String? _bestDefault(List<String> choices, List<ScheduleBlock> all) {
    for (final choice in choices) {
      if (_filtered(all, choice).isNotEmpty) return choice;
    }
    return choices.firstOrNull;
  }

  List<ScheduleBlock> _filtered(List<ScheduleBlock> all, [String? override]) {
    final value = (override ?? _value)?.trim().toLowerCase();
    if (value == null || value.isEmpty) return const [];
    return switch (_lens) {
      _Lens.section => all.where((b) => b.section.trim().toLowerCase() == value).toList(),
      _Lens.teacher => all.where((b) => b.teacherName.trim().toLowerCase() == value).toList(),
      _Lens.room => all.where((b) => (b.room ?? '').trim().toLowerCase() == value).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider);
    final all = scheduleAsync.valueOrNull ?? const <ScheduleBlock>[];
    final year = ref.watch(scheduleYearProvider);
    final students = ref.watch(studentsStreamProvider).valueOrNull ?? const [];
    // Watched here rather than read inside _openEditor. A read on a
    // stream provider nothing is listening to starts it cold and hands
    // back nothing, which is how the editor opened saying the school had
    // no faculty while two teachers were on screen behind it.
    final faculty = (ref.watch(employeesStreamProvider).valueOrNull ?? const <EmployeeSummary>[])
        .where((e) => e.role == UserRole.faculty)
        .toList();
    final assignments = ref.watch(teacherAssignmentsStreamProvider).valueOrNull ?? const [];
    final sections = <String>{
      ...students.map((s) => s.section as String),
      ...assignments.map((a) => a.section as String),
    }.toList();

    final choices = _choicesFor(_lens, all, sections);
    // Computed every build rather than latched on the first one. The
    // timetable arrives a moment after the screen does, and a default
    // chosen before it lands is chosen from an empty list -- which is
    // how this opened on a section nobody had timetabled, showing an
    // empty week that reads as a broken feature.
    final selected = _value ?? _bestDefault(choices, all);
    final shown = _filtered(all, selected);

    ref.listen(scheduleActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(error.toString()),
            duration: const Duration(seconds: 6),
          ));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Class Schedule'),
        actions: [
          if (shown.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.print_outlined),
              tooltip: 'Print this timetable',
              onPressed: () => TimetablePdf.print(
                title: selected ?? 'Timetable',
                subtitle: 'School Year $year',
                blocks: shown,
                branding: ref.read(brandingProvider).valueOrNull ?? SchoolBranding.empty,
                preparedByName:
                    ref.read(authStateProvider).valueOrNull?.fullName ?? 'the office',
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(all, faculty),
        icon: const Icon(Icons.add),
        label: const Text('Add class'),
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('The timetable could not be loaded: $err'),
          ),
        ),
        data: (_) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            SegmentedButton<_Lens>(
              segments: const [
                ButtonSegment(value: _Lens.section, label: Text('Section')),
                ButtonSegment(value: _Lens.teacher, label: Text('Teacher')),
                ButtonSegment(value: _Lens.room, label: Text('Room')),
              ],
              selected: {_lens},
              onSelectionChanged: (selection) => setState(() {
                _lens = selection.first;
                _value = null;
              }),
            ),
            const SizedBox(height: 12),
            if (choices.isEmpty)
              Text(
                _lens == _Lens.room
                    ? 'No rooms have been recorded yet. Rooms are optional -- '
                        'add one to a class and it will appear here.'
                    : 'Nothing to show under this view yet.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: choices.contains(selected) ? selected : choices.first,
                decoration: InputDecoration(
                  labelText: switch (_lens) {
                    _Lens.section => 'Section',
                    _Lens.teacher => 'Teacher',
                    _Lens.room => 'Room',
                  },
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem(value: choice, child: Text(choice)),
                ],
                onChanged: (v) => setState(() => _value = v),
              ),
            const SizedBox(height: 4),
            Text('School Year $year', style: Theme.of(context).textTheme.bodySmall),
            TimetableView(
              blocks: shown,
              showSection: _lens != _Lens.section,
              showTeacher: _lens != _Lens.teacher,
              highlightDay: DateTime.now().weekday,
              onTap: (block) => _openEditor(all, faculty, existing: block),
              emptyMessage: 'Nothing is timetabled here yet.\n\n'
                  'Add a class and it will show up on the student and teacher '
                  'timetables straight away.',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    List<ScheduleBlock> all,
    List<EmployeeSummary> faculty, {
    ScheduleBlock? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _BlockEditor(
        existing: existing,
        faculty: faculty,
        everything: all,
        schoolYear: ref.read(scheduleYearProvider),
      ),
    );
  }
}

class _BlockEditor extends ConsumerStatefulWidget {
  final ScheduleBlock? existing;
  final List<EmployeeSummary> faculty;
  final List<ScheduleBlock> everything;
  final String schoolYear;

  const _BlockEditor({
    required this.existing,
    required this.faculty,
    required this.everything,
    required this.schoolYear,
  });

  @override
  ConsumerState<_BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<_BlockEditor> {
  late final TextEditingController _subject;
  late final TextEditingController _section;
  late final TextEditingController _room;
  late final TextEditingController _start;
  late final TextEditingController _end;
  late int _day;
  EmployeeSummary? _teacher;

  @override
  void initState() {
    super.initState();
    final block = widget.existing;
    _subject = TextEditingController(text: block?.subject ?? '');
    _section = TextEditingController(text: block?.section ?? '');
    _room = TextEditingController(text: block?.room ?? '');
    _start = TextEditingController(text: block == null ? '' : block.startLabel);
    _end = TextEditingController(text: block == null ? '' : block.endLabel);
    _day = block?.dayOfWeek ?? DateTime.now().weekday;
    // On edit, preselect this block's own teacher rather than the first
    // in the list, so saving without touching the dropdown cannot
    // silently hand the class to somebody else.
    _teacher = block == null
        ? widget.faculty.firstOrNull
        : widget.faculty.where((f) => f.uid == block.teacherId).firstOrNull ??
            widget.faculty.firstOrNull;
  }

  @override
  void dispose() {
    _subject.dispose();
    _section.dispose();
    _room.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final start = parseMinuteOfDay(_start.text);
    final end = parseMinuteOfDay(_end.text);
    if (start == null || end == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Enter times like 7:30 AM and 8:30 AM.'),
        ));
      return;
    }

    final ok = await ref.read(scheduleActionControllerProvider.notifier).save(
          blockId: widget.existing?.id,
          subject: _subject.text,
          section: _section.text,
          teacherId: _teacher?.uid ?? '',
          teacherName: _teacher?.fullName ?? '',
          room: _room.text,
          dayOfWeek: _day,
          startMinute: start,
          endMinute: end,
          schoolYear: widget.schoolYear,
          existing: widget.everything,
        );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final block = widget.existing;
    if (block == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this class?'),
        content: Text(
          '${block.subject} for ${block.section}, ${block.dayLabel} ${block.timeLabel}.\n\n'
          'It disappears from the student and teacher timetables straight away.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref.read(scheduleActionControllerProvider.notifier).delete(block.id);
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(scheduleActionControllerProvider).isLoading;
    final all = widget.everything;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add a class' : 'Edit this class'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.faculty.isEmpty)
              const Text('No faculty members yet. Add one under Employee Management first.')
            else
              DropdownButtonFormField<EmployeeSummary>(
                isExpanded: true,
                value: _teacher,
                decoration: const InputDecoration(labelText: 'Teacher'),
                items: [
                  for (final f in widget.faculty)
                    DropdownMenuItem(value: f, child: Text(f.fullName)),
                ],
                onChanged: (v) => setState(() => _teacher = v),
              ),
            const SizedBox(height: 12),
            // Subjects and sections are free text everywhere else in this
            // system, so the editor offers what is already in use without
            // preventing a new one.
            ComboField(
              controller: _subject,
              label: 'Subject',
              suggestions: all.map((b) => b.subject).toList(),
            ),
            const SizedBox(height: 12),
            ComboField(
              controller: _section,
              label: 'Section',
              suggestions: all.map((b) => b.section).toList(),
            ),
            const SizedBox(height: 12),
            ComboField(
              controller: _room,
              label: 'Room (optional)',
              suggestions: all.map((b) => b.room ?? '').where((r) => r.isNotEmpty).toList(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              isExpanded: true,
              value: _day,
              decoration: const InputDecoration(labelText: 'Day'),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(value: day, child: Text(weekdayLabel(day))),
              ],
              onChanged: (v) => setState(() => _day = v ?? _day),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    decoration: const InputDecoration(labelText: 'Starts', hintText: '7:30 AM'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _end,
                    decoration: const InputDecoration(labelText: 'Ends', hintText: '8:30 AM'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: busy ? null : _delete,
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || _teacher == null ? null : _save,
          child: Text(widget.existing == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
