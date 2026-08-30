import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../../../core/constants/user_roles.dart';
import '../../../parent_portal/presentation/controllers/parent_controller.dart'
    show myChildrenProvider;
import '../controllers/messaging_controller.dart';

/// Starting a new thread, from either side.
///
/// Two steps, and which two depends on who is looking: a parent picks a
/// child and then one of that child's teachers; a teacher picks a
/// section, then a student, then that student's parent. Both end in the
/// same callable, which checks the relationship again -- this sheet is
/// what makes it usable, not what makes it safe.
///
/// Returns the conversation id, or null if nothing was started.
Future<String?> showNewConversationSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _NewConversationSheet(),
  );
}

class _NewConversationSheet extends ConsumerStatefulWidget {
  const _NewConversationSheet();

  @override
  ConsumerState<_NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState extends ConsumerState<_NewConversationSheet> {
  String? _section;
  String? _studentId;
  String? _studentName;

  Future<void> _open(String studentId, String otherUid) async {
    final controller = ref.read(messagingActionControllerProvider.notifier);
    final id = await controller.startConversation(
      studentId: studentId,
      otherUid: otherUid,
    );
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            // The server's refusal, which says something useful: "that
            // teacher does not teach this student's class".
            controller.errorMessage ?? 'That conversation could not be opened.',
          ),
        ));
      return;
    }
    Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = ref.watch(authStateProvider).valueOrNull?.role;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('New message', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Flexible(
              child: switch (role) {
                UserRole.parent => _ParentFlow(
                    studentId: _studentId,
                    onPickChild: (id, name) => setState(() {
                      _studentId = id;
                      _studentName = name;
                    }),
                    studentName: _studentName,
                    onPickTeacher: (teacherUid) => _open(_studentId!, teacherUid),
                  ),
                UserRole.faculty => _TeacherFlow(
                    section: _section,
                    studentId: _studentId,
                    studentName: _studentName,
                    onPickSection: (section) => setState(() {
                      _section = section;
                      _studentId = null;
                      _studentName = null;
                    }),
                    onPickStudent: (id, name) => setState(() {
                      _studentId = id;
                      _studentName = name;
                    }),
                    onPickParent: (parentUid) => _open(_studentId!, parentUid),
                  ),
                _ => Text(
                    // Deliberately only these two. Messaging here is
                    // between a family and the teacher who teaches
                    // their child; a school that needs to tell everyone
                    // something has announcements.
                    'Messaging is between parents and their children\'s '
                    'teachers.',
                    style: theme.textTheme.bodyMedium,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentFlow extends ConsumerWidget {
  final String? studentId;
  final String? studentName;
  final void Function(String id, String name) onPickChild;
  final ValueChanged<String> onPickTeacher;

  const _ParentFlow({
    required this.studentId,
    required this.studentName,
    required this.onPickChild,
    required this.onPickTeacher,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (studentId == null) {
      final children = ref.watch(myChildrenProvider).valueOrNull ?? const [];
      if (children.isEmpty) {
        return const Text('No children are linked to this account yet.');
      }
      // Skipped when there is only one child: a step with one option is
      // a tap that asks nothing.
      if (children.length == 1) {
        final only = children.first;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onPickChild(only.id, only.fullName),
        );
      }
      return _Options(
        prompt: 'Which child is this about?',
        children: [
          for (final child in children)
            ListTile(
              title: Text(child.fullName),
              subtitle: Text(child.classLabel),
              onTap: () => onPickChild(child.id, child.fullName),
            ),
        ],
      );
    }

    final child = ref
        .watch(myChildrenProvider)
        .valueOrNull
        ?.where((c) => c.id == studentId)
        .firstOrNull;
    final teachers =
        ref.watch(teachersForSectionProvider(child?.section ?? ''));

    return teachers.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Text('Their teachers could not be loaded: $err'),
      data: (list) => list.isEmpty
          ? Text(
              'No teachers are assigned to ${studentName ?? 'this class'} yet. '
              'The office assigns them.',
            )
          : _Options(
              prompt: 'Who would you like to message about $studentName?',
              children: [
                for (final teacher in list)
                  ListTile(
                    title: Text(teacher.teacherName),
                    subtitle: Text(
                      teacher.isAdviser
                          // Worth naming: the adviser is the one person
                          // responsible for the class as a whole, and
                          // usually who a parent means.
                          ? 'Class adviser · ${teacher.subject}'
                          : teacher.subject,
                    ),
                    onTap: () => onPickTeacher(teacher.teacherId),
                  ),
              ],
            ),
    );
  }
}

class _TeacherFlow extends ConsumerWidget {
  final String? section;
  final String? studentId;
  final String? studentName;
  final ValueChanged<String> onPickSection;
  final void Function(String id, String name) onPickStudent;
  final ValueChanged<String> onPickParent;

  const _TeacherFlow({
    required this.section,
    required this.studentId,
    required this.studentName,
    required this.onPickSection,
    required this.onPickStudent,
    required this.onPickParent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section == null) {
      final sections = ref.watch(mySectionsProvider);
      return sections.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('Your classes could not be loaded: $err'),
        data: (list) => list.isEmpty
            ? const Text(
                'You are not assigned to any section yet. The office assigns '
                'them.',
              )
            : _Options(
                prompt: 'Which class?',
                children: [
                  for (final name in list)
                    ListTile(title: Text(name), onTap: () => onPickSection(name)),
                ],
              ),
      );
    }

    if (studentId == null) {
      final students = ref.watch(studentsInSectionProvider(section!));
      return students.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Text('That roll could not be loaded: $err'),
        data: (list) => list.isEmpty
            ? Text('Nobody is enrolled in $section yet.')
            : _Options(
                prompt: 'Which student?',
                children: [
                  for (final student in list)
                    ListTile(
                      title: Text(student.name),
                      onTap: () => onPickStudent(student.id, student.name),
                    ),
                ],
              ),
      );
    }

    final parents = ref.watch(parentsForStudentProvider(studentId!));
    return parents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Text('Their guardians could not be loaded: $err'),
      data: (list) => list.isEmpty
          ? Text(
              // A real and common state, worth saying rather than
              // showing an empty list: plenty of families have no
              // portal account.
              '$studentName has no parent account linked yet. The registrar '
              'links them.',
            )
          : _Options(
              prompt: 'Whose guardian?',
              children: [
                for (final parent in list)
                  ListTile(
                    title: Text(parent.name.isEmpty ? 'Guardian' : parent.name),
                    subtitle: Text('Parent of $studentName'),
                    onTap: () => onPickParent(parent.uid),
                  ),
              ],
            ),
    );
  }
}

class _Options extends StatelessWidget {
  final String prompt;
  final List<Widget> children;

  const _Options({required this.prompt, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(prompt, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Flexible(child: ListView(shrinkWrap: true, children: children)),
      ],
    );
  }
}
