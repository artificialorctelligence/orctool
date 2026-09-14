import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/store.dart';

import '../fakes.dart';

void main() {
  late Store store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  final t0 = DateTime(2026, 9, 13, 12);
  Future<void> put(String run, DateTime ts, {String inst = 'compass', String kind = 'session', Limits limits = const Limits()}) =>
      store.insert(instrument: inst, runId: run, kind: kind, ts: ts, data: {'heading': 247.5, 'field': 48.2}, limits: limits);

  test('rows come back decoded, in time order, with ts', () async {
    await put('r1', t0.add(const Duration(seconds: 1)));
    await put('r1', t0);
    final rows = await store.rows('r1');
    expect(rows.map((r) => r['ts']), [t0, t0.add(const Duration(seconds: 1))]);
    expect(rows.first['heading'], 247.5);
  });

  test('runs summarises each run_id, newest first, filtered by kind', () async {
    await put('r1', t0);
    await put('r1', t0.add(const Duration(minutes: 1)));
    await put('log-w', t0.add(const Duration(hours: 1)), inst: 'weather', kind: 'log');
    final all = await store.runs();
    expect(all.map((r) => r.runId), ['log-w', 'r1']);
    expect(all.last.rows, 2);
    expect(all.last.first, t0);
    expect(all.last.last, t0.add(const Duration(minutes: 1)));
    expect((await store.runs(kind: 'log')).single.instrument, 'weather');
  });

  test('retention by age deletes rows older than retentionDays at write time', () async {
    await put('old', t0.subtract(const Duration(days: 31)));
    await put('new', t0, limits: const Limits(retentionDays: 30));
    expect((await store.runs()).map((r) => r.runId), ['new']);
  });

  test('retention by cap deletes the oldest rows until under capBytes', () async {
    const tiny = Limits(retentionDays: 365, capBytes: 120); // each row is 30 bytes of data
    for (var i = 0; i < 10; i++) {
      await put('r', t0.add(Duration(seconds: i)), limits: tiny);
    }
    expect(await store.totalBytes(), lessThanOrEqualTo(120));
    final rows = await store.rows('r');
    expect(rows.last['ts'], t0.add(const Duration(seconds: 9)), reason: 'newest survives');
    expect(rows.length, 4);
  });

  test('kind is constrained to session or log', () async {
    await expectLater(put('r', t0, kind: 'bogus'), throwsA(anything));
  });
}
