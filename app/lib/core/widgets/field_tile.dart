import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// A form row that opens a picker instead of accepting typing.
///
/// Date and time pickers were bare [ListTile]s sitting between text fields
/// in five different forms: square where the fields were rounded, unfilled
/// where the fields were filled, and in one case carrying a hand-written
/// border of its own. They read as list rows that had wandered into a
/// form, which is exactly what they were.
///
/// This is not a real [InputDecorator] -- it takes no input, so it has no
/// focus, error or floating-label states to honour. It borrows the same
/// well, border and metrics so that a row you tap and a row you type in
/// sit together as one form.
class FieldTile extends StatelessWidget {
  final IconData icon;

  /// What the field is, shown when nothing has been chosen yet -- so an
  /// empty row still says "Due date" rather than sitting blank.
  final String label;

  /// The chosen value. Null renders [label] in the hint's colour, matching
  /// an empty text field beside it.
  final String? value;

  final VoidCallback onTap;

  const FieldTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final glass = GlassPalette.of(context);
    final shape = BorderRadius.circular(14);
    final isEmpty = value == null;

    return Material(
      color: glass.fieldFill,
      borderRadius: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: shape,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: glass.fieldBorder),
          ),
          // Matches inputDecorationTheme's contentPadding, so a picker row
          // and a text field are the same height in the same column.
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value ?? label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isEmpty
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(Icons.expand_more,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
