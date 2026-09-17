import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/core/store.dart';
import 'package:orctool/shell/instruments_screen.dart';
import 'package:orctool/shell/settings_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler, ThrowingScheduler;
import '../fakes.dart';

class Blocked extends FakeInstrument {
  Blocked() : super(id: 'blocked', name: 'Blocked');
  @override
  Future<String?> logPrecondition() async => 'Needs a permission first';
}

void main() {
  late Registry reg;
  late SpyScheduler sched;
  late Store store;
  String? sharedName;
  List<int>? sharedBytes;

  setUp(() async {
    sched = SpyScheduler();
    store = await memoryStore();
    sharedName = null;
    sharedBytes = null;
    reg = Registry([FakeInstrument(id: 'a', name: 'Alpha'), FakeInstrument(id: 'b', name: 'Beta', canLog: false), Blocked()], await memoryPrefs(), sched);
    await reg.probe();
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: SettingsScreen(prefs: reg.prefs, registry: reg, store: store, share: (b, n) async {
      sharedBytes = b;
      sharedName = n;
    }))));
    await t.pumpAndSettle();
  }

  testWidgets('skin, retention and cap persist', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('skin')));
    await t.pumpAndSettle();
    await t.tap(find.text('Console').last);
    await t.pumpAndSettle();
    expect(reg.prefs.skinId, 'console');
    await t.tap(find.byKey(const Key('retention')));
    await t.pumpAndSettle();
    await t.tap(find.text('90 days').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cap')));
    await t.pumpAndSettle();
    await t.tap(find.text('200 MB').last);
    await t.pumpAndSettle();
    expect(reg.prefs.limits.retentionDays, 90);
    expect(reg.prefs.limits.capBytes, 200 * 1024 * 1024);
  });

  testWidgets('Instruments: show toggle, log toggle only when canLog, precondition blocks logging', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('log-a')), findsOneWidget);
    expect(find.byKey(const Key('log-b')), findsNothing);
    expect(find.byKey(const Key('details-b')), findsOneWidget, reason: 'More exists even without logging');
    expect(find.text('Show'), findsOneWidget, reason: 'the switches are labelled');
    expect(find.text('Log'), findsOneWidget);
    await t.tap(find.byKey(const Key('show-b')));
    await t.pumpAndSettle();
    expect(reg.isShown('b'), isFalse);
    await t.tap(find.byKey(const Key('log-a')));
    await t.pumpAndSettle();
    expect(reg.isLogging('a'), isTrue);
    expect(sched.calls, ['schedule a 60']);
    await t.tap(find.byKey(const Key('log-blocked')));
    await t.pumpAndSettle();
    expect(reg.isLogging('blocked'), isFalse);
    expect(find.text('Needs a permission first'), findsOneWidget);
  });

  testWidgets('details page sets the interval', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('interval')));
    await t.pumpAndSettle();
    await t.tap(find.text('daily').last);
    await t.pumpAndSettle();
    expect(reg.settingsFor(reg.byId('a')!).interval, LogInterval.daily);
  });

  testWidgets('long instrument names do not overflow on narrow screens', (t) async {
    final narrowReg = Registry([FakeInstrument(id: 'long', name: 'A Very Long Instrument Name Indeed', canLog: true)], await memoryPrefs(), SpyScheduler());
    await narrowReg.probe();
    await t.pumpWidget(MaterialApp(
      theme: skinById('plain').light,
      home: Scaffold(body: SizedBox(width: 320, child: InstrumentsScreen(registry: narrowReg, store: store))),
    ));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('log settings save failure reverts the form and shows a message', (t) async {
    final failReg = Registry([FakeInstrument(id: 'a', name: 'Alpha')], await memoryPrefs(), ThrowingScheduler());
    await failReg.probe();
    final a = failReg.byId('a')!;
    await failReg.prefs.setLogging('a', true);
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: SettingsScreen(prefs: failReg.prefs, registry: failReg, store: store))));
    await t.pumpAndSettle();
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('interval')));
    await t.pumpAndSettle();
    await t.tap(find.text('daily').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Could not save'), findsOneWidget);
    expect(failReg.settingsFor(a).interval, LogInterval.hourly);
  });

  testWidgets('More on a non-logging instrument has no logging section but has export and clear', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-b')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('interval')), findsNothing);
    expect(find.text('Export all recordings'), findsOneWidget);
    expect(find.text('Clear history'), findsOneWidget);
  });

  testWidgets('export shares one .xlsx with a sheet per run', (t) async {
    final t0 = DateTime(2026, 9, 14, 22, 1);
    await store.insert(instrument: 'a', runId: 's1', kind: 'session', ts: t0, data: {'v': 1}, limits: reg.prefs.limits);
    await store.insert(instrument: 'a', runId: 'l1', kind: 'log', ts: t0.add(const Duration(hours: 1)), data: {'v': 2}, limits: reg.prefs.limits);
    await store.insert(instrument: 'b', runId: 'x', kind: 'session', ts: t0, data: {'v': 3}, limits: reg.prefs.limits);
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.text('Export all recordings'));
    await t.pumpAndSettle();
    expect(sharedName, 'a.xlsx');
    final x = Excel.decodeBytes(sharedBytes!);
    expect(x.tables.keys.toSet(), {'Session 2026-09-14 2201', 'Log from 2026-09-14 2301'});
  });

  testWidgets('clear history asks first, then deletes only that instrument', (t) async {
    final t0 = DateTime(2026, 9, 14, 22, 1);
    await store.insert(instrument: 'a', runId: 's1', kind: 'session', ts: t0, data: {'v': 1}, limits: reg.prefs.limits);
    await store.insert(instrument: 'b', runId: 'x', kind: 'session', ts: t0, data: {'v': 3}, limits: reg.prefs.limits);
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear history'));
    await t.pumpAndSettle();
    expect(find.textContaining('Deletes all 1 row'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect((await store.runs(instrument: 'a')).length, 1, reason: 'cancel keeps the data');
    await t.tap(find.text('Clear history'));
    await t.pumpAndSettle();
    await t.tap(find.text('Clear'));
    await t.pumpAndSettle();
    expect(await store.runs(instrument: 'a'), isEmpty);
    expect((await store.runs(instrument: 'b')).length, 1);
    expect(find.textContaining('0 rows'), findsOneWidget, reason: 'the page shows the new count');
  });
}
