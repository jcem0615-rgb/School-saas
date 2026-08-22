import 'package:flutter/material.dart';

import '../theme/glass.dart';

/// The navigation tile every portal dashboard is built from.
///
/// There were eight copies of this, one per dashboard, each a private
/// `_QuickLinkTile` that had drifted slightly from the others -- different
/// widths, different corner radii, one with a border and one without. They
/// are one widget now, which is also the only way a change to the surface
/// treatment lands on all ten portals at once instead of eight times.
///
/// `blur: false` is deliberate: a dashboard shows six to nine of these, and
/// a BackdropFilter each would be the most expensive thing on the screen
/// for the least benefit -- at tile size the fill, the lit edge and the
/// shadow carry the material on their own.
class GlassTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Marks the one action on a dashboard that is not ordinary navigation --
  /// the student's emergency button. Tints the icon well rather than
  /// recolouring the whole tile, so it reads as urgent without turning the
  /// dashboard into a warning screen.
  final bool emphasis;

  const GlassTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = emphasis ? theme.colorScheme.error : theme.colorScheme.primary;

    return SizedBox(
      width: 148,
      child: GlassSurface(
        blur: false,
        radius: 20,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: accent.withValues(alpha: 0.12),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Icon(icon, size: 22, color: accent),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
