import 'package:flutter/material.dart';

/// What Material's theme does not carry: the rail and title-bar language.
class OrcTheme extends ThemeExtension<OrcTheme> {
  const OrcTheme({
    required this.accent,
    required this.onAccent,
    required this.panel,
    required this.ground,
    required this.railRadius,
    required this.railStripe,
    required this.uppercase,
    this.displayFont,
  });

  final Color accent;
  final Color onAccent;
  final Color panel;
  final Color ground;
  final double railRadius;
  final bool railStripe;
  final bool uppercase;
  final String? displayFont;

  static OrcTheme of(BuildContext context) => Theme.of(context).extension<OrcTheme>()!;

  String text(String s) => uppercase ? s.toUpperCase() : s;

  @override
  OrcTheme copyWith({Color? accent, Color? onAccent, Color? panel, Color? ground, double? railRadius, bool? railStripe, bool? uppercase, String? displayFont}) => OrcTheme(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        panel: panel ?? this.panel,
        ground: ground ?? this.ground,
        railRadius: railRadius ?? this.railRadius,
        railStripe: railStripe ?? this.railStripe,
        uppercase: uppercase ?? this.uppercase,
        displayFont: displayFont ?? this.displayFont,
      );

  @override
  OrcTheme lerp(OrcTheme? other, double t) {
    if (other == null) return this;
    return OrcTheme(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      railRadius: railRadius + (other.railRadius - railRadius) * t,
      railStripe: t < 0.5 ? railStripe : other.railStripe,
      uppercase: t < 0.5 ? uppercase : other.uppercase,
      displayFont: t < 0.5 ? displayFont : other.displayFont,
    );
  }
}

class Skin {
  const Skin({required this.id, required this.name, required this.light, required this.dark});
  final String id;
  final String name;
  final ThemeData light;
  final ThemeData dark;
}
