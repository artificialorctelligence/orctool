import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/recorder.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/instrument_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

class Controlled extends FakeInstrument {
  Controlled({super.canLog}) : super(id: 'c', name: 'Controlled');
  final ctl = StreamController<Reading>.broadcast();
  @override
  Stream<Reading> live() => ctl.stream;
}

void main() {
  late Registry reg;
  late Recorder rec;

  Future<void> pump(WidgetTester t, Instrument i) async {
    reg = Registry([i], await memoryPrefs(), SpyScheduler());
    await reg.probe();
    rec = Recorder(await memoryStore(), reg.prefs);
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: InstrumentScreen(instrument: i, registry: reg, recorder: rec))));
    await t.pump();
  }

  testWidgets('live and detail bands render each reading', (t) async {
    final i = Controlled();
    await pump(t, i);
    i.ctl.add(Reading(DateTime(2026), const {'v': 7}));
    await t.pump();
    await t.pump();
    expect(find.text('live 7'), findsOneWidget);
    expect(find.text('detail 7'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // dispose the recording bar's timer
  });

  testWidgets('record button starts and stops a session; timer shows', (t) async {
    final i = Controlled();
    await pump(t, i);
    await t.tap(find.byKey(const Key('record')));
    await t.pump();
    expect(rec.recording, isTrue);
    expect(rec.instrument, same(i));
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('00:0'), findsOneWidget);
    await t.tap(find.byKey(const Key('record')));
    // Recorder.stop() awaits a broadcast StreamSubscription.cancel(), whose
    // Future only settles on the real event loop — pump() alone never
    // resolves it (confirmed: even five plain pumps left it pending), so a
    // runAsync round-trip is required before the widget reflects the stop.
    await t.runAsync(() async {});
    await t.pump();
    expect(rec.recording, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('log chip only when logging is on; absent when canLog is false', (t) async {
    final i = Controlled();
    await pump(t, i);
    expect(find.textContaining('Log:'), findsNothing);
    await reg.setLogging(i, true);
    await t.pump();
    expect(find.text('Log: hourly'), findsOneWidget);
    final noLog = Controlled(canLog: false);
    await pump(t, noLog);
    expect(find.textContaining('Log:'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a stream error shows the error band with Retry and disables recording', (t) async {
    final i = Controlled();
    await pump(t, i);
    i.ctl.addError(StateError('no data'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('no data'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await t.tap(find.byKey(const Key('record')));
    await t.pump();
    expect(rec.recording, isFalse);
    await t.tap(find.text('Retry'));
    await t.pump();
    i.ctl.add(Reading(DateTime(2026), const {'v': 8}));
    await t.pump();
    await t.pump();
    expect(find.text('live 8'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
