import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/store.dart';
import 'package:orctool/core/workbook.dart';

void main() {
  final t0 = DateTime(2026, 9, 14, 22, 1);
  RunSummary run(String id, String kind, DateTime first) =>
      RunSummary(runId: id, instrument: 'compass', kind: kind, rows: 2, first: first, last: first.add(const Duration(seconds: 30)));

  test('one sheet per run, named by kind and start time, header row then rows', () {
    final bytes = workbook([
      (run('s1', 'session', t0), [
        {'ts': t0, 'heading': 247.5, 'field': 48},
        {'ts': t0.add(const Duration(seconds: 1)), 'heading': 248.0, 'field': 49},
      ]),
      (run('l1', 'log', t0.add(const Duration(hours: 1))), [
        {'ts': t0.add(const Duration(hours: 1)), 'heading': 10.0},
      ]),
    ]);
    final x = Excel.decodeBytes(bytes);
    expect(x.tables.keys.toList(), ['Session 2026-09-14 2201', 'Log from 2026-09-14 2301']);
    final s = x.tables['Session 2026-09-14 2201']!;
    expect(s.rows.length, 3);
    expect(s.rows[0].map((c) => c?.value.toString()).toList(), ['ts', 'field', 'heading']);
    expect(s.rows[1][0]!.value.toString(), '2026-09-14 22:01:00.000');
    expect(s.rows[1][2]!.value, isA<DoubleCellValue>().having((v) => v.value, 'heading', 247.5));
    expect(s.rows[1][1]!.value, isA<IntCellValue>().having((v) => v.value, 'field', 48));
  });

  test('two runs starting in the same minute get distinct sheet names', () {
    final bytes = workbook([
      (run('a', 'session', t0), [{'ts': t0, 'v': 1}]),
      (run('b', 'session', t0.add(const Duration(seconds: 20))), [{'ts': t0, 'v': 2}]),
    ]);
    expect(Excel.decodeBytes(bytes).tables.keys.toList(), ['Session 2026-09-14 2201', 'Session 2026-09-14 2201 (2)']);
  });

  test('no runs gives an empty workbook that still opens', () {
    expect(Excel.decodeBytes(workbook([])).tables, isNotEmpty);
  });
}
