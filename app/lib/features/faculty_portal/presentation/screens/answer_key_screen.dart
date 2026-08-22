import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/coursework_item.dart';
import '../controllers/faculty_controller.dart';

/// Where a teacher writes the correct answers.
///
/// One answer per line, which is the fastest thing to type and the
/// easiest to check by eye against a paper master. The line number is the
/// question number.
///
/// This screen has no student-facing counterpart and must never get one:
/// the key lives in a collection firestore.rules does not let students
/// read, and marking happens server-side against it. If the answers ever
/// reached the device being marked, the feature would be decorative.
class AnswerKeyScreen extends ConsumerStatefulWidget {
  final CourseworkItem item;
  const AnswerKeyScreen({super.key, required this.item});

  @override
  ConsumerState<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends ConsumerState<AnswerKeyScreen> {
  final _controller = TextEditingController();
  final _pointsController = TextEditingController(text: '1');
  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    _pointsController.dispose();
    super.dispose();
  }

  List<String> get _answers => _controller.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final answers = _answers;
    final points = double.tryParse(_pointsController.text) ?? 0;

    if (answers.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Write at least one answer, one per line.'),
        ));
      return;
    }
    if (points <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Marks per question must be more than zero.')));
      return;
    }

    setState(() => _saving = true);
    final ok = await ref.read(facultyActionControllerProvider.notifier).saveAnswerKey(
          courseworkId: widget.item.id,
          answers: answers,
          pointsPerQuestion: points,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            'Answer key saved. ${answers.length} questions, '
            'marked automatically from now on.',
          ),
        ));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyAsync = ref.watch(answerKeyProvider(widget.item.id));

    ref.listen(facultyActionControllerProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    });

    // Prefill once. Rebinding on every stream tick would fight the
    // teacher as they type.
    if (!_loaded && keyAsync.hasValue) {
      _loaded = true;
      final key = keyAsync.value;
      if (key != null) {
        _controller.text = key.answers.join('\n');
        _pointsController.text = key.pointsPerQuestion.toString();
      }
    }

    final answers = _answers;
    final points = double.tryParse(_pointsController.text) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Answer Key')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.item.title, style: theme.textTheme.titleMedium),
          Text(
            '${widget.item.type.displayLabel} · ${widget.item.subject} - ${widget.item.section}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('What this can mark', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Answers are matched exactly, ignoring capitals and '
                    'spaces around the word. That works for multiple '
                    'choice, one-word answers and numbers. It cannot mark '
                    'an essay — leave the key empty for work you want to '
                    'read yourself.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Students never see this page or these answers.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Correct answers — one per line',
              hintText: 'Mitosis\nMeiosis\nFour\nProphase',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pointsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Marks per question',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            answers.isEmpty
                ? 'No questions yet.'
                : '${answers.length} questions · ${(answers.length * points).toStringAsFixed(answers.length * points % 1 == 0 ? 0 : 1)} marks total',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Save key and re-mark'),
          ),
          const SizedBox(height: 8),
          Text(
            'Saving re-marks every answer already handed in, so fixing a '
            'wrong key corrects the whole class at once.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
