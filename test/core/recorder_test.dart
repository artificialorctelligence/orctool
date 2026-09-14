import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/recorder.dart';

import '../fakes.dart';

class ErrorInstrument extends FakeInstrument {
  ErrorInstrument() : super(id: 'err');
  @override
  Stream<Reading> live() async* {
    yield script.first;
    throw StateError('sensor gone');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 9, 13, 12);

  test('a session writes exactly the streamed readings under one run_id', () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    final i = FakeInstrument(id: 'compass', script: [
      Reading(t0, const {'heading': 1}),
      Reading(t0.add(const Duration(seconds: 1)), const {'heading': 2}),
    ]);
    rec.start(i);
    expect(rec.recording, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let the stream drain and the inserts land
    await rec.stop();
    expect(rec.recording, isFalse);
    final runs = await store.runs();
    expect(runs.single.instrument, 'compass');
    expect(runs.single.kind, 'session');
    expect(runs.single.rows, 2);
    expect((await store.rows(runs.single.runId)).map((r) => r['heading']), [1, 2]);
  });

  test('a stream error keeps the rows so far and stops cleanly', () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    rec.start(ErrorInstrument());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rec.recording, isFalse);
    expect(rec.error, contains('sensor gone'));
    expect((await store.runs()).single.rows, 1);
  });

  test('a scheduled sample writes one log row under the log run, silently skips failures', () async {
    final store = await memoryStore();
    final prefs = await memoryPrefs();
    await prefs.setLogRun('weather', 'weather-run');
    await prefs.setLogSettings('weather', const LogSettings(interval: LogInterval.daily));
    final i = FakeInstrument(id: 'weather', script: [Reading(t0, const {'temp': 19.3})]);
    await runScheduledSample(i, store, prefs);
    await runScheduledSample(i, store, prefs);
    expect(i.log.interval, LogInterval.daily, reason: 'settings handed over before sampling');
    final run = (await store.runs()).single;
    expect(run.runId, 'weather-run');
    expect(run.kind, 'log');
    expect(run.rows, 2);
    await runScheduledSample(ErrorInstrumentSample(), store, prefs);
    expect((await store.runs()).single.rows, 2, reason: 'failure wrote nothing');
  });
}

class ErrorInstrumentSample extends FakeInstrument {
  ErrorInstrumentSample() : super(id: 'weather');
  @override
  Future<Reading> sample() => Future.error(TimeoutException('no fix'));
}
