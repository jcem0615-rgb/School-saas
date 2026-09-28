import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/controllers/auth_controller.dart'
    show authStateProvider;
import '../../../../core/constants/user_roles.dart';
import '../../../parent_portal/presentation/controllers/parent_controller.dart'
    show myChildrenProvider;
import '../../domain/entities/conversation.dart';
import '../controllers/messaging_controller.dart';

/// Starting a new thread, from either side.
///
/// A parent picks a child and then one of that child's teachers; a
/// teacher picks a class, then a student, then that student's guardian.
/// Both end in the same callable, which checks the relationship again --
/// this sheet is what makes it usable, not what makes it safe.
///
/// ## Why dropdowns rather than a wizard
///
/// It used to be a stack of lists: tap a class, the sheet became a list
/// of students, tap a student, it became a list of guardians. Three
/// screens, no way back, and no way to see what you had already chosen.
/// Picking the wrong class meant closing the sheet and starting again.
///
/// Three dropdowns show the whole choice at once and let any part of it
/// be changed without losing the rest. The one thing that has to happen
/// when an earlier choice changes is that the later ones are cleared --
/// a student from the class you just moved away from is not a student
/// you meant to write about.
///
/// Returns the conversation id, or null if nothing was started.
Future<String?> showNewConversationSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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
  String? _recipientUid;
  bool _starting = false;

  /// Who the thread is about, for the button and for the callable.
  String? get _aboutStudentId => _studentId;

  Future<void> _start() async {
    final studentId = _aboutStudentId;
    final recipient = _recipientUid;
    if (studentId == null || recipient == null) return;

    setState(() => _starting = true);
    final controller = ref.read(messagingActionControllerProvider.notifier);
    final id = await controller.startConversation(
      studentId: studentId,
      otherUid: recipient,
    );
    if (!mounted) return;
    if (id == null) {
      setState(() => _starting = false);
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
        4,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New message', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              switch (role) {
                UserRole.parent => _parentPickers(),
                UserRole.faculty => _teacherPickers(),
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
              if (role == UserRole.parent || role == UserRole.faculty) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed:
                      _starting || _aboutStudentId == null || _recipientUid == null
                          ? null
                          : _start,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Start message'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _parentPickers() {
    final children = ref.watch(myChildrenProvider).valueOrNull ?? const [];
    if (children.isEmpty) {
      return const _Nothing('No children are linked to this account yet.');
    }

    // One child is not a choice, so it is made rather than asked. The
    // dropdown still shows who it is -- a parent writing about the wrong
    // child should be able to see that before they send.
    final childId = _studentId ?? (children.length == 1 ? children.first.id : null);
    if (childId != _studentId && childId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _studentId = childId);
      });
    }
    final child = children.where((c) => c.id == childId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Picker<String>(
          label: 'About which child',
          value: childId,
          items: [
            for (final one in children)
              DropdownMenuItem(value: one.id, child: Text(one.fullName)),
          ],
          onChanged: (id) => setState(() {
            _studentId = id;
            // Their teachers are not this one's teachers.
            _recipientUid = null;
          }),
        ),
        const SizedBox(height: 16),
        _AsyncPicker<dynamic>(
          label: 'Message',
          hintWhenWaiting: 'Choose a child first',
          ready: child != null,
          request: ref.watch(teachersForSectionProvider(child?.section ?? '')),
          emptyMessage: 'No teachers are assigned to that class yet. The '
              'office assigns them.',
          value: _recipientUid,
          itemsOf: (list) => [
            for (final teacher in list)
              DropdownMenuItem<String>(
                value: teacher.teacherId,
                child: Text(
                  teacher.isAdviser
                      // Worth naming: the adviser is the one person
                      // responsible for the class as a whole, and
                      // usually who a parent means.
                      ? '${teacher.teacherName} — class adviser'
                      : '${teacher.teacherName} — ${teacher.subject}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (uid) => setState(() => _recipientUid = uid),
        ),
      ],
    );
  }

  Widget _teacherPickers() {
    final sections = ref.watch(mySectionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AsyncPicker<String>(
          label: 'Class',
          ready: true,
          request: sections,
          emptyMessage:
              'You are not assigned to any section yet. The office assigns them.',
          value: _section,
          itemsOf: (list) => [
            for (final name in list)
              DropdownMenuItem<String>(value: name, child: Text(name)),
          ],
          onChanged: (name) => setState(() {
            _section = name;
            // A student from the class just moved away from is not a
            // student anybody meant to write about.
            _studentId = null;
            _recipientUid = null;
          }),
        ),
        const SizedBox(height: 16),
        _AsyncPicker<MessageablePerson>(
          label: 'Student',
          hintWhenWaiting: 'Choose a class first',
          ready: _section != null,
          request: ref.watch(studentsInSectionProvider(_section ?? '')),
          emptyMessage: 'Nobody is enrolled in that class yet.',
          value: _studentId,
          itemsOf: (list) => [
            for (final student in list)
              DropdownMenuItem<String>(
                value: student.id,
                child: Text(student.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => setState(() {
            _studentId = id;
            _recipientUid = null;
          }),
        ),
        const SizedBox(height: 16),
        _AsyncPicker<MessageableGuardian>(
          // The dropdown this screen was missing: which guardian.
          label: 'Guardian to message',
          hintWhenWaiting: 'Choose a student first',
          ready: _studentId != null,
          request: ref.watch(parentsForStudentProvider(_studentId ?? '')),
          // A real and common state, worth saying rather than showing an
          // empty list: plenty of families have no portal account.
          emptyMessage: 'That student has no guardian account linked yet. '
              'The registrar links them.',
          value: _recipientUid,
          itemsOf: (list) => [
            for (final guardian in list)
              DropdownMenuItem<String>(
                value: guardian.uid,
                child: Text(
                  guardian.name.isEmpty ? 'Guardian' : guardian.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (uid) => setState(() => _recipientUid = uid),
        ),
      ],
    );
  }
}

/// One dropdown over a list that is still being fetched.
///
/// Every state of it is a dropdown rather than a spinner replacing the
/// form: the labels stay put, nothing jumps, and a list that is empty
/// or failed says so underneath itself instead of taking over the sheet.
/// That is the difference from what this replaced, where one failed
/// query left the whole screen as a line of red text.
class _AsyncPicker<T> extends StatelessWidget {
  final String label;

  /// Shown when an earlier choice has not been made yet.
  final String? hintWhenWaiting;

  /// Whether the choice this one depends on has been made.
  final bool ready;

  final AsyncValue<List<T>> request;
  final String emptyMessage;
  final String? value;
  final List<DropdownMenuItem<String>> Function(List<T> list) itemsOf;
  final ValueChanged<String?> onChanged;

  const _AsyncPicker({
    required this.label,
    required this.ready,
    required this.request,
    required this.emptyMessage,
    required this.value,
    required this.itemsOf,
    required this.onChanged,
    this.hintWhenWaiting,
  });

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return _Picker<String>(
        label: label,
        value: null,
        items: const [],
        onChanged: null,
        hint: hintWhenWaiting,
      );
    }

    return request.when(
      loading: () => _Picker<String>(
        label: label,
        value: null,
        items: const [],
        onChanged: null,
        hint: 'Loading…',
      ),
      error: (err, _) => _Picker<String>(
        label: label,
        value: null,
        items: const [],
        onChanged: null,
        hint: 'Could not be loaded',
        // The reason, small and underneath, for whoever has to act on
        // it -- not as the entire contents of the sheet.
        help: '$err',
        isError: true,
      ),
      data: (list) {
        final items = itemsOf(list);
        if (items.isEmpty) {
          return _Picker<String>(
            label: label,
            value: null,
            items: const [],
            onChanged: null,
            hint: 'None',
            help: emptyMessage,
          );
        }
        return _Picker<String>(
          label: label,
          // Guarded: a value left over from a list that has since
          // changed is a dropdown that throws rather than one that looks
          // wrong, and it throws in the frame it is built.
          value: items.any((i) => i.value == value) ? value : null,
          items: items,
          onChanged: onChanged,
        );
      },
    );
  }
}

class _Picker<T> extends StatelessWidget {
  final String label;
  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final String? hint;
  final String? help;
  final bool isError;

  const _Picker({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.help,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      items: items,
      onChanged: onChanged,
      hint: hint == null ? null : Text(hint!),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        helperText: isError ? null : help,
        helperMaxLines: 3,
        errorText: isError ? help : null,
        errorMaxLines: 3,
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  final String message;
  const _Nothing(this.message);

  @override
  Widget build(BuildContext context) =>
      Text(message, style: Theme.of(context).textTheme.bodyMedium);
}
