import 'package:flutter/material.dart';

import 'skin.dart';

ThemeData _plain(Brightness b) {
  final base = ThemeData(colorSchemeSeed: Colors.blue, brightness: b);
  final cs = base.colorScheme;
  return base.copyWith(extensions: [
    OrcTheme(
      accent: cs.primary,
      onAccent: cs.onPrimary,
      panel: cs.surfaceContainerHighest,
      ground: cs.surface,
      railRadius: 6,
      railStripe: false,
      uppercase: false,
    ),
  ]);
}

/// Material 3, follows the system light/dark. The default.
final plainSkin = Skin(id: 'plain', name: 'Plain', light: _plain(Brightness.light), dark: _plain(Brightness.dark));
