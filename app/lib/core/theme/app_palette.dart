import 'package:flutter/material.dart';

/// The colours the glass is made of.
///
/// Kept apart from [ThemeData] because a glass surface needs values Material
/// has no slot for: what the ambient background is doing behind the pane,
/// how much light the pane's top edge catches, how far the shadow falls.
/// Reading those off `colorScheme` would mean guessing at alpha values in
/// twenty widgets instead of deciding them once.
///
/// Light and dark are designed as two different rooms rather than one
/// inverted: in light the panes are white held up against a pale sky, in
/// dark they are a thin film of light over deep blue. Inverting the light
/// values would give the usual muddy grey-on-grey.
@immutable
class GlassPalette extends ThemeExtension<GlassPalette> {
  /// The two ends of the ambient wash the whole app sits on.
  final Color backdropTop;
  final Color backdropBottom;

  /// Two soft colour fields drifting in that wash. They are what makes the
  /// panes read as glass -- a frosted surface over a flat colour just
  /// looks like a lighter flat colour.
  final Color auroraPrimary;
  final Color auroraSecondary;

  /// The pane itself.
  final Color paneFill;

  /// Slightly denser, for surfaces that carry small text -- dialogs,
  /// menus, anything where legibility beats transparency.
  final Color paneFillStrong;

  /// The lit edge. A real pane catches light along its top and one side,
  /// which is most of what sells the effect at a glance.
  final Color paneHighlight;
  final Color paneBorder;

  final Color paneShadow;

  const GlassPalette({
    required this.backdropTop,
    required this.backdropBottom,
    required this.auroraPrimary,
    required this.auroraSecondary,
    required this.paneFill,
    required this.paneFillStrong,
    required this.paneHighlight,
    required this.paneBorder,
    required this.paneShadow,
  });

  /// Panes of white glass against a pale sky.
  static const light = GlassPalette(
    backdropTop: Color(0xFFF2F5FB),
    backdropBottom: Color(0xFFE2E8F4),
    auroraPrimary: Color(0x332E5FD9),
    auroraSecondary: Color(0x2A18A0A8),
    paneFill: Color(0xC4FFFFFF),
    paneFillStrong: Color(0xF2FFFFFF),
    paneHighlight: Color(0xE6FFFFFF),
    paneBorder: Color(0x33203A63),
    paneShadow: Color(0x1A16233D),
  );

  /// A thin film of light over deep blue.
  static const dark = GlassPalette(
    backdropTop: Color(0xFF0A1020),
    backdropBottom: Color(0xFF141D33),
    auroraPrimary: Color(0x4D3B6FE0),
    auroraSecondary: Color(0x3D6C5CE7),
    paneFill: Color(0x14FFFFFF),
    paneFillStrong: Color(0xE60E1626),
    paneHighlight: Color(0x2EFFFFFF),
    paneBorder: Color(0x24FFFFFF),
    paneShadow: Color(0x59000000),
  );

  @override
  GlassPalette copyWith({
    Color? backdropTop,
    Color? backdropBottom,
    Color? auroraPrimary,
    Color? auroraSecondary,
    Color? paneFill,
    Color? paneFillStrong,
    Color? paneHighlight,
    Color? paneBorder,
    Color? paneShadow,
  }) {
    return GlassPalette(
      backdropTop: backdropTop ?? this.backdropTop,
      backdropBottom: backdropBottom ?? this.backdropBottom,
      auroraPrimary: auroraPrimary ?? this.auroraPrimary,
      auroraSecondary: auroraSecondary ?? this.auroraSecondary,
      paneFill: paneFill ?? this.paneFill,
      paneFillStrong: paneFillStrong ?? this.paneFillStrong,
      paneHighlight: paneHighlight ?? this.paneHighlight,
      paneBorder: paneBorder ?? this.paneBorder,
      paneShadow: paneShadow ?? this.paneShadow,
    );
  }

  @override
  GlassPalette lerp(ThemeExtension<GlassPalette>? other, double t) {
    if (other is! GlassPalette) return this;
    return GlassPalette(
      backdropTop: Color.lerp(backdropTop, other.backdropTop, t)!,
      backdropBottom: Color.lerp(backdropBottom, other.backdropBottom, t)!,
      auroraPrimary: Color.lerp(auroraPrimary, other.auroraPrimary, t)!,
      auroraSecondary: Color.lerp(auroraSecondary, other.auroraSecondary, t)!,
      paneFill: Color.lerp(paneFill, other.paneFill, t)!,
      paneFillStrong: Color.lerp(paneFillStrong, other.paneFillStrong, t)!,
      paneHighlight: Color.lerp(paneHighlight, other.paneHighlight, t)!,
      paneBorder: Color.lerp(paneBorder, other.paneBorder, t)!,
      paneShadow: Color.lerp(paneShadow, other.paneShadow, t)!,
    );
  }

  /// Convenience: the palette for the current theme.
  static GlassPalette of(BuildContext context) =>
      Theme.of(context).extension<GlassPalette>() ?? light;
}
