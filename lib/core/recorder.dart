import 'dart:async';

import 'package:flutter/foundation.dart';

import 'instrument.dart';
import 'prefs.dart';
import 'store.dart';

/// One session at a time: starting on another instrument ends the running one.
class Recorder extends ChangeNotifier {
  Recorder(this.store, this.prefs);
  final Store store;
  final Prefs prefs;

  StreamSubscription<Reading>? _sub;
  Future<void> _pending = Future.value();
  Instrument? instrument;
  DateTime? startedAt;
  String? _runId;
  String? error;
  Object? _session;

  bool get recording => _sub != null;

  Future<void> start(Instrument i) async {
    if (recording) await stop();
    final session = _session = Object();
    instrument = i;
    startedAt = DateTime.now();
    error = null;
    _runId = '${i.id}-${startedAt!.millisecondsSinceEpoch}';
    _sub = i.live().listen(
      (r) => _pending = _pending.then((_) => store.insert(
            instrument: i.id, runId: _runId!, kind: 'session', ts: r.ts, data: i.toRow(r), limits: prefs.limits)
          // A failed write ends the session with a visible message (spec §5); earlier rows stay.
          .catchError((Object e) => _fail(session, 'Could not save: $e'))),
      // A sensor error ends the session; rows written so far stay (spec §5).
      onError: (Object e) => _fail(session, '$e'),
      onDone: stop,
    );
    notifyListeners();
  }

  /// Returns once every queued row has been written.
  Future<void> stop() async {
    final sub = _sub;
    _sub = null; // before any await, so a concurrent start() is never clobbered
    _session = null;
    await sub?.cancel();
    await _pending;
    notifyListeners();
  }

  /// Only the session that failed may stop the recorder. Must NOT await stop():
  /// stop() awaits _pending, whose tail is the very catchError that calls this.
  void _fail(Object session, String message) {
    if (session != _session) return;
    error = message;
    stop();
  }
}

/// The scheduler's callback: one sample, one row. Failures are silent — the
/// next scheduled run is the retry (spec §5).
Future<void> runScheduledSample(Instrument i, Store store, Prefs prefs) async {
  try {
    i.log = prefs.logSettings(i.id) ?? i.defaultLogSettings;
    final r = await i.sample().timeout(i.sampleTimeout);
    await store.insert(instrument: i.id, runId: prefs.logRun(i.id) ?? i.id, kind: 'log', ts: r.ts, data: i.toRow(r), limits: prefs.limits);
  } catch (e) {
    // Spec §5: no row, no retry; the gap shows in Records.
    debugPrint('scheduled sample ${i.id} failed: $e');
  }
}
