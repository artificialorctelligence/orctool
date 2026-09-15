import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/csv.dart';

void main() {
  test('ts first, union of keys sorted, quoting where needed', () {
    final csv = toCsv([
      {'ts': DateTime.utc(2026, 9, 13, 12), 'heading': 247.5, 'note': 'a,b'},
      {'ts': DateTime.utc(2026, 9, 13, 12, 0, 1), 'field': 48.2, 'note': 'say "hi"'},
    ]);
    expect(csv.split('\n'), [
      'ts,field,heading,note',
      '2026-09-13T12:00:00.000Z,,247.5,"a,b"',
      '2026-09-13T12:00:01.000Z,48.2,,"say ""hi"""',
    ]);
  });

  test('empty', () => expect(toCsv([]), ''));
}
