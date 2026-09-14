import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/core/store.dart';
import 'package:orctool/shell/records_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

void main() {
  late Store store;
  late Registry reg;
  final t0 = DateTime(2026, 9, 13, 14, 2);

  setUp(() async {
    store = await memoryStore();
    final prefs = await memoryPrefs();
    reg = Registry([FakeInstrument(id: 'compass', name: 'Compass'), FakeInstrument(id: 'weather', name: 'Weather')], prefs, SpyScheduler());
    await reg.probe();
    await store.insert(instrument: 'compass', runId: 's1', kind: 'session', ts: t0, data: {'heading': 247}, limits: prefs.limits);
    await store.insert(instrument: 'compass', runId: 's1', kind: 'session', ts: t0.add(const Duration(seconds: 42)), data: {'heading': 248}, limits: prefs.limits);
    await store.insert(instrument: 'weather', runId: 'l1', kind: 'log', ts: t0.add(const Duration(hours: 1)), data: {'temp': 19.3}, limits: prefs.limits);
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: RecordsScreen(store: store, registry: reg, prefs: reg.prefs))));
    await t.pumpAndSettle();
  }

  testWidgets('lists runs newest first with instrument name, kind, rows; storage line', (t) async {
    await pump(t);
    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(find.descendant(of: tiles.first, matching: find.text('Weather')), findsOneWidget);
    expect(find.textContaining('Log ·'), findsOneWidget);
    expect(find.textContaining('Session ·'), findsOneWidget);
    expect(find.text('2 rows'), findsOneWidget);
    expect(find.textContaining('of 50 MB'), findsOneWidget);

    // The kind word goes through orc.text() too: under the uppercase console skin it reads SESSION.
    await t.pumpWidget(MaterialApp(theme: skinById('console').dark, home: Scaffold(body: RecordsScreen(store: store, registry: reg, prefs: reg.prefs))));
    await t.pumpAndSettle();
    expect(find.textContaining('SESSION ·'), findsOneWidget);
  });

  testWidgets('run table builds rows lazily, not all at once', (t) async {
    for (var i = 0; i < 3000; i++) {
      await store.insert(instrument: 'compass', runId: 'big', kind: 'session', ts: t0.add(Duration(seconds: i)), data: {'heading': 247 + i}, limits: reg.prefs.limits);
    }
    await pump(t);
    await t.tap(find.text('Compass').first);
    await t.pumpAndSettle();
    expect(find.text('247'), findsOneWidget);
    expect(find.byType(Row).evaluate().length, lessThan(200));
  });

  testWidgets('filter chips', (t) async {
    await pump(t);
    await t.tap(find.text('Logs'));
    await t.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
  });

  testWidgets('tapping a run opens its table; share hands over CSV', (t) async {
    String? shared;
    await t.pumpWidget(MaterialApp(
      theme: skinById('plain').light,
      home: Scaffold(body: RecordsScreen(store: store, registry: reg, prefs: reg.prefs, share: (csv, name) async => shared = '$name\n$csv')),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Compass'));
    await t.pumpAndSettle();
    expect(find.text('247'), findsOneWidget);
    expect(find.text('248'), findsOneWidget);
    await t.tap(find.byIcon(Icons.share));
    await t.pumpAndSettle();
    expect(shared, startsWith('compass-s1.csv\nts,heading\n'));
  });
}
