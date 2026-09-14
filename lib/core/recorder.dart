import 'dart:async';

import 'package:flutter/foundation.dart';

import 'instrument.dart';
import 'prefs.dart';
import 'store.dart';

/// One session at a time: an extra sink on the instrument's live stream.
class Recorder extends ChangeNotifier {
  Recorder(this.store, this.prefs);
  final Store store;
  final Prefs prefs;

  StreamSubscription<Reading>? _sub;
  Instrument? instrument;
  DateTime? startedAt;
  String? _runId;
  String? error;

  bool get recording => _sub != null;

  void start(Instrument i) {
    if (recording) return;
    instrument = i;
    startedAt = DateTime.now();
    error = null;
    _runId = '${i.id}-${startedAt!.millisecondsSinceEpoch}';
    _sub = i.live().listen(
      (r) => store
          .insert(instrument: i.id, runId: _runId!, kind: 'session', ts: r.ts, data: i.toRow(r), limits: prefs.limits)
          .catchError((Object e) => _fail('Could not save: $e')),
      onError: (Object e) => _fail('$e'),
      onDone: stop,
    );
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  void _fail(String message) {
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
