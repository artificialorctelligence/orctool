import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class Limits {
  const Limits({this.retentionDays = 30, this.capBytes = 50 * 1024 * 1024});
  final int retentionDays;
  final int capBytes;
}

class RunSummary {
  const RunSummary({required this.runId, required this.instrument, required this.kind, required this.rows, required this.first, required this.last});
  final String runId;
  final String instrument;
  final String kind;
  final int rows;
  final DateTime first;
  final DateTime last;
}

/// One table for every instrument. `data` is the instrument's toRow() as JSON.
class Store {
  Store._(this._db);
  final Database _db;
  int _total = 0;

  static Future<Store> open(String path) async {
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute(
          "CREATE TABLE readings(id INTEGER PRIMARY KEY, instrument TEXT NOT NULL, run_id TEXT NOT NULL, kind TEXT NOT NULL, ts INTEGER NOT NULL, data TEXT NOT NULL, CHECK(kind IN ('session','log')))");
      await db.execute('CREATE INDEX idx_inst_ts ON readings(instrument, ts)');
      await db.execute('CREATE INDEX idx_run ON readings(run_id)');
      await db.execute('CREATE INDEX idx_ts ON readings(ts)');
    });
    final s = Store._(db);
    s._total = await s.totalBytes();
    return s;
  }

  Future<void> close() => _db.close();

  Future<void> insert({required String instrument, required String runId, required String kind, required DateTime ts, required Map<String, num> data, required Limits limits}) async {
    final json = jsonEncode(data);
    await prune(limits, now: ts, incoming: json.length);
    await _db.insert('readings', {'instrument': instrument, 'run_id': runId, 'kind': kind, 'ts': ts.millisecondsSinceEpoch, 'data': json});
    _total += json.length;
  }

  /// Age prune on every write (indexed delete; the total is rescanned only when it removed rows);
  /// cap prune from the cached total, so the cap is never exceeded by more than one row.
  Future<void> prune(Limits limits, {DateTime? now, int incoming = 0}) async {
    final t = now ?? DateTime.now();
    final cutoff = t.subtract(Duration(days: limits.retentionDays)).millisecondsSinceEpoch;
    final removed = await _db.delete('readings', where: 'ts < ?', whereArgs: [cutoff]);
    if (removed > 0) _total = await totalBytes();
    while (_total + incoming > limits.capBytes && _total > 0) {
      final count = Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM readings')) ?? 0;
      if (count == 0) break;
      final excess = _total + incoming - limits.capBytes;
      final n = (excess * count / _total).ceil().clamp(1, count);
      await _db.rawDelete('DELETE FROM readings WHERE id IN (SELECT id FROM readings ORDER BY ts ASC, id ASC LIMIT ?)', [n]);
      _total = await totalBytes();
    }
  }

  Future<int> totalBytes() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM readings')) ?? 0;

  Future<List<RunSummary>> runs({String? kind}) async {
    final r = await _db.rawQuery(
      'SELECT run_id, instrument, kind, COUNT(*) n, MIN(ts) t0, MAX(ts) t1 FROM readings'
      '${kind == null ? '' : ' WHERE kind = ?'} GROUP BY run_id ORDER BY t1 DESC',
      kind == null ? null : [kind],
    );
    return [
      for (final m in r)
        RunSummary(
          runId: m['run_id'] as String,
          instrument: m['instrument'] as String,
          kind: m['kind'] as String,
          rows: m['n'] as int,
          first: DateTime.fromMillisecondsSinceEpoch(m['t0'] as int),
          last: DateTime.fromMillisecondsSinceEpoch(m['t1'] as int),
        ),
    ];
  }

  /// Each row is {'ts': DateTime, ...decoded data}.
  Future<List<Map<String, Object?>>> rows(String runId) async {
    final r = await _db.query('readings', columns: ['ts', 'data'], where: 'run_id = ?', whereArgs: [runId], orderBy: 'ts ASC');
    return [
      for (final m in r)
        {
          'ts': DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
          ...(jsonDecode(m['data'] as String) as Map).cast<String, Object?>(),
        },
    ];
  }
}
