import 'package:flutter/material.dart';

import 'skin.dart';

const _ground = Color(0xFF0B0B10);
const _panel = Color(0xFF1E2230);
const _accent = Color(0xFFF2B56B);

final ThemeData _console = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark, surface: _ground, primary: _accent, onPrimary: _ground),
  scaffoldBackgroundColor: _ground,
  fontFamily: 'Antonio',
  extensions: const [
    OrcTheme(
      accent: _accent,
      onAccent: _ground,
      panel: _panel,
      ground: _ground,
      railRadius: 8,
      railStripe: true,
      uppercase: true,
      displayFont: 'Antonio',
    ),
  ],
);

/// Ship's-console look: near-black, one warm accent, condensed uppercase type.
/// Adjacent to a certain famous interface; deliberately not it.
final consoleSkin = Skin(id: 'console', name: 'Console', light: _console, dark: _console);
