import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'class_passcode.dart';

/// Asks for the code the teacher read out.
///
/// It asks every time rather than trying without one first and asking
/// only when refused. Two reasons: a wasted round trip in front of a
/// class is a lesson somebody is late for, and reading a refusal to
/// work out whether it was about the code means the words of an error
/// message quietly become an interface.
///
/// A lesson with no code -- one opened before codes existed -- is
/// joined by leaving the box empty, which is why the button is never
/// disabled for an empty field.
class PasscodePrompt extends StatefulWidget {
  final String subject;

  /// Tries the code. Returns the refusal to show, or null once in.
  ///
  /// The dialog stays open on a refusal and keeps what was typed: a
  /// child who mistyped one character should fix that character, not
  /// start again from a closed dialog.
  final Future<String?> Function(String passcode) onJoin;

  const PasscodePrompt({super.key, required this.subject, required this.onJoin});

  @override
  State<PasscodePrompt> createState() => _PasscodePromptState();
}

class _PasscodePromptState extends State<PasscodePrompt> {
  final _typed = TextEditingController();
  String? _refusal;
  bool _trying = false;

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_trying) return;
    setState(() {
      _trying = true;
      _refusal = null;
    });
    final refusal = await widget.onJoin(normaliseClassPasscode(_typed.text));
    if (!mounted) return;
    if (refusal == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _trying = false;
      _refusal = refusal;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Class code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your teacher reads this out at the start of ${widget.subject}.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            enabled: !_trying,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            // Eight characters and a dash between the halves of it.
            // Longer than that is a paste of something else.
            maxLength: passcodeLength + 1,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z-]')),
              TextInputFormatter.withFunction((old, now) =>
                  now.copyWith(text: now.text.toUpperCase())),
            ],
            style: const TextStyle(letterSpacing: 3, fontSize: 20),
            decoration: InputDecoration(
              hintText: 'A1B2-C3D4',
              border: const OutlineInputBorder(),
              counterText: '',
              errorText: _refusal,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _trying ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Never disabled for an empty box: a lesson opened before
          // codes existed is joined by leaving it empty.
          onPressed: _trying ? null : _submit,
          child: _trying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}
