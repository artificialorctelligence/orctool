import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/prefs.dart';
import 'package:orctool/core/recorder.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/shell.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

void main() {
  late Prefs prefs;
  late Registry reg;

  Future<void> pump(WidgetTester t, {String skin = 'plain'}) async {
    await t.pumpWidget(MaterialApp(
      theme: skinById(skin).light,
      home: Shell(
        registry: reg,
        recorder: Recorder(await memoryStore(), prefs),
        prefs: prefs,
        store: await memoryStore(),
        instrumentBuilder: (_, i) => Text('screen:${i.id}'),
        recordsBuilder: (_) => const Text('screen:records'),
        settingsBuilder: (_) => const Text('screen:settings'),
      ),
    ));
    await t.pumpAndSettle();
  }

  setUp(() async {
    prefs = await memoryPrefs();
    reg = Registry([FakeInstrument(id: 'motion', name: 'Motion'), FakeInstrument(id: 'compass', name: 'Compass')], prefs, SpyScheduler());
    await reg.probe();
  });

  testWidgets('rail lists instruments then Records then Settings; first instrument is selected', (t) async {
    await pump(t);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Compass'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('screen:motion'), findsOneWidget);
  });

  testWidgets('tapping a rail entry switches content and does not move the rail', (t) async {
    await pump(t);
    await t.tap(find.text('Records'));
    await t.pumpAndSettle();
    expect(find.text('screen:records'), findsOneWidget);
    expect(prefs.railOut, isTrue);
    expect(find.text('Compass'), findsOneWidget);
  });

  testWidgets('tapping the title bar slides the rail in, names the instrument, persists', (t) async {
    await pump(t);
    await t.tap(find.text('Compass'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('title-instrument')), findsNothing);
    await t.tap(find.byKey(const Key('title-bar')));
    await t.pumpAndSettle();
    expect(prefs.railOut, isFalse);
    expect(find.text('Motion'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('title-instrument')), matching: find.text('Compass')), findsOneWidget);
    await t.tap(find.byKey(const Key('title-bar')));
    await t.pumpAndSettle();
    expect(prefs.railOut, isTrue);
  });

  testWidgets('console skin uppercases the rail', (t) async {
    await pump(t, skin: 'console');
    expect(find.text('COMPASS'), findsOneWidget);
  });

  testWidgets('hiding the selected instrument falls back to the first rail entry', (t) async {
    await pump(t);
    await reg.setShown('motion', false);
    await t.pumpAndSettle();
    expect(find.text('Motion'), findsNothing);
    expect(find.text('screen:compass'), findsOneWidget);
  });
}
