import 'package:flutter/material.dart';

/// A text field that also offers a dropdown of known values.
///
/// Deliberately not a [DropdownButtonFormField]: grade levels, sections and
/// subjects are free text in this system, not a fixed enum. A school can
/// invent "Grade 11 - STEM B" mid-year, and a plain dropdown would make
/// that unenterable while a plain text field would lose the convenience of
/// picking an existing value. This gives both -- type anything, or tap the
/// arrow to choose from what already exists in the school's data.
class ComboField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  const ComboField({
    super.key,
    required this.controller,
    required this.label,
    required this.suggestions,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
    this.onChanged,
  });

  @override
  State<ComboField> createState() => _ComboFieldState();
}

class _ComboFieldState extends State<ComboField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pickFromList() async {
    // Distinct, sorted, and blank-free: suggestions are gathered from live
    // records, which routinely contain duplicates and empty strings.
    final options = widget.suggestions
        .where((s) => s.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    if (options.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('No existing ${widget.label.toLowerCase()} yet — type a new one.')),
        );
      return;
    }

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select ${widget.label}',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => ListTile(
                  title: Text(options[i]),
                  onTap: () => Navigator.of(sheetContext).pop(options[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null) return;
    widget.controller.text = picked;
    widget.onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_drop_down),
          tooltip: 'Choose existing',
          onPressed: widget.enabled ? _pickFromList : null,
        ),
      ),
    );
  }
}
