/// Rows as Records stores them: {'ts': DateTime, ...columns}.
String toCsv(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return '';
  final keys = {for (final r in rows) ...r.keys}..remove('ts');
  final cols = ['ts', ...keys.toList()..sort()];
  String cell(Object? v) {
    final s = switch (v) { null => '', DateTime d => d.toUtc().toIso8601String(), _ => '$v' };
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }
  return [cols.join(','), for (final r in rows) cols.map((c) => cell(r[c])).join(',')].join('\n');
}
