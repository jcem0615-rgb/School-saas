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

  /// A short word in the corner, for a tile whose contents are happening
  /// right now -- "LIVE" on the online class while a lesson is running.
  ///
  /// Only ever a word or two. A tile is a signpost; anything that needs
  /// a sentence needs the screen behind it.
  final String? badge;

  const GlassTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasis = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = emphasis ? theme.colorScheme.error : theme.colorScheme.primary;

    return SizedBox(
      width: 148,
      // Fixed, not intrinsic: a two-line label ("Assignments & Exams")
      // made its tile taller than the one-line tile beside it, which on a
      // phone -- two columns wide -- turned the grid ragged. Tall enough
      // for two lines at the largest text scale the label allows.
      height: 132,
      child: GlassSurface(
        blur: false,
        radius: 20,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        child: Stack(
          // Expand, not the default loose fit: a Stack gives its
          // unpositioned children loose constraints, and the column
          // would shrink-wrap -- taking the centred label off the
          // centre of every tile in the app.
          fit: StackFit.expand,
          children: [
            Column(
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
            if (badge != null)
              Positioned(
                top: 0,
                right: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      badge!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
