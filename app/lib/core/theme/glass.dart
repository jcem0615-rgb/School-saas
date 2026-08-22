import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_palette.dart';

/// The wash every screen sits on.
///
/// Installed once, above the router, so panes have something to refract.
/// Frosted glass over a flat colour just looks like a lighter flat colour;
/// the two drifting colour fields are what make a blurred surface read as
/// glass rather than as opacity.
///
/// Painted with a [CustomPaint] rather than stacked [Container]s with
/// gradients: it is one draw call under the whole app either way, and the
/// radial fields want centres and radii expressed against the real size
/// rather than alignment fractions.
class AmbientBackground extends StatelessWidget {
  final Widget child;
  const AmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final glass = GlassPalette.of(context);
    return CustomPaint(
      painter: _AmbientPainter(glass),
      isComplex: true,
      willChange: false,
      child: child,
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final GlassPalette glass;
  const _AmbientPainter(this.glass);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [glass.backdropTop, glass.backdropBottom],
        ).createShader(rect),
    );

    // Two fields, deliberately off-centre and different sizes. Symmetry
    // here reads as a wallpaper; asymmetry reads as light in a room.
    void field(Offset centre, double radius, Color colour) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    final span = size.shortestSide;
    field(Offset(size.width * 0.14, size.height * 0.06), span * 1.05,
        glass.auroraPrimary);
    field(Offset(size.width * 0.92, size.height * 0.78), span * 0.9,
        glass.auroraSecondary);
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) => oldDelegate.glass != glass;
}

/// A pane of glass.
///
/// Blur is opt-out rather than always on. A [BackdropFilter] is one of the
/// more expensive things a Flutter frame can contain, and a dashboard is a
/// grid of eight of these; on the web build that is the difference between
/// a screen that settles instantly and one that hitches while it composites.
/// Small repeated surfaces pass `blur: false` and get the fill, the lit
/// edge and the shadow, which carries the material at tile size. Large
/// surfaces -- panels, dialogs, the app bar -- keep the real thing.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool blur;

  /// Denser fill for surfaces carrying small text.
  final bool opaque;

  /// Lifts the pane: a deeper shadow and a brighter edge, for the one
  /// surface on screen that is meant to be in front.
  final bool elevated;

  final VoidCallback? onTap;

  const GlassSurface({
    super.key,
    required this.child,
    this.padding,
    this.radius = 20,
    this.blur = true,
    this.opaque = false,
    this.elevated = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glass = GlassPalette.of(context);
    final shape = BorderRadius.circular(radius);

    Widget content =
        padding == null ? child : Padding(padding: padding!, child: child);

    if (onTap != null) {
      // The InkWell wraps the content rather than overlaying it. An
      // overlay draws the ripple just as well, but it makes the tappable
      // region a sibling of the label instead of its ancestor -- so the
      // semantics do not merge and a screen reader announces an unnamed
      // button. The transparent Material sits inside the decoration, so
      // the ripple still lands on top of the fill.
      content = Material(
        color: Colors.transparent,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, borderRadius: shape, child: content),
      );
    }

    final Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        // Top-down rather than flat: a pane catches more light along its
        // upper edge, and the falloff is most of what sells it.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            opaque ? glass.paneFillStrong : glass.paneHighlight,
            opaque ? glass.paneFillStrong : glass.paneFill,
          ],
        ),
        border: Border.all(color: glass.paneBorder, width: 1),
      ),
      child: content,
    );

    Widget result = ClipRRect(
      borderRadius: shape,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: pane,
            )
          : pane,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: glass.paneShadow,
            blurRadius: elevated ? 34 : 18,
            offset: Offset(0, elevated ? 14 : 7),
          ),
        ],
      ),
      child: result,
    );
  }
}
