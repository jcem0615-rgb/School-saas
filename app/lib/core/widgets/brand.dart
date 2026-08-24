import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The LogicClass mark.
///
/// Vector, not a bitmap: the mark is shown at 44px on a phone login and
/// well over 100 on a desktop window, and a raster sized for one is soft
/// on the other. The launcher icons are PNGs rendered from this same
/// artwork, so there is one drawing behind every appearance of it.
class LogicClassMark extends StatelessWidget {
  final double size;

  const LogicClassMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    // The navy that carries the L is within a few percent of the dark
    // backdrop, so on a dark theme the letter disappears and the nodes
    // read as empty rings. The dark variant lifts it to a tint of the
    // same colour; everything else about the drawing is identical.
    final dark = Theme.of(context).brightness == Brightness.dark;

    return SvgPicture.asset(
      dark
          ? 'assets/brand/logicclass-logo-dark.svg'
          : 'assets/brand/logicclass-logo.svg',
      width: size,
      height: size,
      // No background in either copy -- it would sit as a pale square on
      // a glass pane. The launcher icon keeps its ground, because a home
      // screen needs one.
      placeholderBuilder: (_) => SizedBox(width: size, height: size),
    );
  }
}

/// Who built the app, shown where it will not compete with the school's
/// own name.
///
/// The school is the thing on screen; this is a maker's mark, so it sits
/// at the bottom of the login, quiet, and repeats once in the app's
/// About screen rather than following the user around.
class PoweredByLogicGrid extends StatelessWidget {
  /// Lightens the text for use on the login pane, where it sits under a
  /// form rather than in a list.
  final bool subdued;

  const PoweredByLogicGrid({super.key, this.subdued = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = subdued
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return Semantics(
      label: 'Powered by LogicGrid',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/brand/logicgrid-logo.svg',
            width: 18,
            height: 18,
            placeholderBuilder: (_) => const SizedBox(width: 18, height: 18),
          ),
          const SizedBox(width: 8),
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Powered by '),
                  TextSpan(
                    text: 'LogicGrid',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colour,
                    ),
                  ),
                ],
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ),
        ],
      ),
    );
  }
}
