import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/skins/all.dart';
import 'package:orctool/skins/skin.dart';

void main() {
  test('two skins; unknown id falls back to plain', () {
    expect(skins.map((s) => s.id), ['plain', 'console']);
    expect(skinById('nope').id, 'plain');
  });

  test('every ThemeData carries an OrcTheme', () {
    for (final s in skins) {
      expect(s.light.extension<OrcTheme>(), isNotNull, reason: s.id);
      expect(s.dark.extension<OrcTheme>(), isNotNull, reason: s.id);
    }
  });

  test('console is uppercase Antonio; plain is neither', () {
    final c = skinById('console').dark.extension<OrcTheme>()!;
    expect(c.uppercase, isTrue);
    expect(c.displayFont, 'Antonio');
    expect(c.text('Compass'), 'COMPASS');
    final p = skinById('plain').light.extension<OrcTheme>()!;
    expect(p.uppercase, isFalse);
    expect(p.text('Compass'), 'Compass');
  });

  test('no colour or radius literals outside lib/skins', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (f.path.startsWith('lib/skins/') || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'Color\(0x|Colors\.[a-z]').hasMatch(src)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
