import 'package:excel/excel.dart';

import 'csv.dart';
import 'store.dart';

/// An .xlsx with one sheet per run: a header row, then one row per reading with
/// the time in local wall-clock. Opens in Excel, LibreOffice and OpenOffice.
List<int> workbook(List<(RunSummary, List<Map<String, Object?>>)> runs) {
  final x = Excel.createExcel();
  final blank = x.getDefaultSheet();
  final used = <String>{};
  for (final (run, rows) in runs) {
    var name = sheetName(run);
    for (var n = 2; !used.add(name); n++) {
      name = '${sheetName(run)} ($n)';
    }
    final sheet = x[name];
    final cols = columnsOf(rows);
    sheet.appendRow([for (final c in cols) TextCellValue(c)]);
    for (final r in rows) {
      sheet.appendRow([for (final c in cols) _cell(r[c])]);
    }
  }
  if (blank != null && runs.isNotEmpty) x.delete(blank);
  return x.encode()!;
}

/// Excel caps sheet names at 31 characters and forbids `: \ / ? * [ ]`, hence HHMM.
String sheetName(RunSummary run) {
  final t = run.first.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp = '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}${two(t.minute)}';
  return '${run.kind == 'log' ? 'Log from' : 'Session'} $stamp';
}

CellValue? _cell(Object? v) => switch (v) {
      null => null,
      DateTime d => TextCellValue(d.toLocal().toString()),
      int i => IntCellValue(i),
      double d => DoubleCellValue(d),
      _ => TextCellValue('$v'),
    };
