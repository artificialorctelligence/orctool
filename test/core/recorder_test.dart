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

/// A session instrument whose stream never completes on its own (no onDone) —
/// used wherever a test needs to observe recorder state well after the single
/// reading was written, without the natural end-of-stream racing it.
class OpenInstrument extends FakeInstrument {
  OpenInstrument({super.id = 'open', super.script});
  @override
  Stream<Reading> live() {
    late StreamController<Reading> c;
    c = StreamController<Reading>(onListen: () => Future.microtask(() => c.add(script.first)));
    return c.stream;
  }
}

/// Emits one reading then a stream error (triggering _fail's fire-and-forget
/// stop()), but its subscription takes 20 ms to actually cancel — wide enough
/// to start a new session while that stop() is still mid-flight.
class SlowCancelErrorInstrument extends FakeInstrument {
  SlowCancelErrorInstrument() : super(id: 'slowCancel');
  @override
  Stream<Reading> live() {
    late StreamController<Reading> controller;
    controller = StreamController<Reading>(
      onListen: () => Future.microtask(() {
        controller.add(script.first);
        controller.addError(StateError('sensor gone'));
      }),
      onCancel: () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    return controller.stream;
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
    // Not a wall-clock wait: flushes the microtask queue so the fake's
    // Stream.fromIterable (which defers even its first item to a scheduled
    // microtask) has actually emitted before stop() cancels it — independent
    // of the _pending flush stop() now does for rows already in flight.
    await Future<void>.delayed(Duration.zero);
    await rec.stop();
    expect(rec.recording, isFalse);
    final runs = await store.runs();
    expect(runs.single.instrument, 'compass');
    expect(runs.single.kind, 'session');
    expect(runs.single.rows, 2);
    expect((await store.rows(runs.single.runId)).map((r) => r['heading']), [1, 2]);
  });

  test('starting on another instrument ends the running session first', () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    final a = FakeInstrument(id: 'a', script: [Reading(t0, const {'v': 1})]);
    final b = FakeInstrument(id: 'b', script: [Reading(t0, const {'v': 2})]);
    rec.start(a);
    await Future<void>.delayed(Duration.zero);
    await rec.start(b);
    expect(rec.instrument, same(b));
    await Future<void>.delayed(Duration.zero);
    await rec.stop();
    final runs = await store.runs();
    expect(runs.map((r) => r.instrument).toSet(), {'a', 'b'});
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

  test('a store write failure ends the session with a visible error', () async {
    final store = await memoryStore();
    await store.close();
    final rec = Recorder(store, await memoryPrefs());
    rec.start(OpenInstrument());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rec.error, contains('Could not save'));
    expect(rec.recording, isFalse);
  });

  test("_fail's fire-and-forget stop() cannot orphan a session started while it is still cancelling", () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    rec.start(SlowCancelErrorInstrument());
    // Let the reading + error land: onError -> _fail -> stop() (unawaited), now
    // 20 ms into cancelling. A correct stop() has already cleared _sub by now
    // (before awaiting cancel), so recording reads false here.
    await Future<void>.delayed(Duration.zero);
    expect(rec.recording, isFalse);
    final b = OpenInstrument(id: 'b', script: [Reading(t0, const {'v': 2})]);
    await rec.start(b); // races the still-in-flight cancel() from the earlier stop()
    // Wait past that 20 ms cancel: a buggy stop() that nulls _sub *after* the
    // await would clobber B's subscription here.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rec.recording, isTrue);
    expect(rec.instrument, same(b));
    expect(rec.error, isNull, reason: "B's own start() resets error; A's failure must not leak into B");
    await rec.stop();
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
