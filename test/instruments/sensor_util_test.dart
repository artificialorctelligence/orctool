import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/sensor_util.dart';

void main() {
  test('firstEventWithin: true on an event, false on silence, false on error', () async {
    expect(await firstEventWithin(Stream.value(1), const Duration(milliseconds: 50)), isTrue);
    expect(await firstEventWithin(StreamController<int>().stream, const Duration(milliseconds: 20)), isFalse);
    expect(await firstEventWithin(Stream<int>.error(StateError('x')), const Duration(milliseconds: 50)), isFalse);
  });

  test('merge2 emits on a-events once b has a value, carrying the latest b', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final out = <(int, String)>[];
    final sub = merge2(a.stream, b.stream).listen(out.add);
    a.add(1); // no b yet: nothing
    await Future<void>.delayed(Duration.zero);
    b.add('x');
    a.add(2);
    b.add('y');
    a.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(out, [(2, 'x'), (3, 'y')]);
    await sub.cancel();
    expect(a.hasListener, isFalse, reason: 'cancel propagates');
    expect(b.hasListener, isFalse, reason: 'cancel propagates to both');
  });
  throttleTests();
}

void throttleTests() {
  test('throttle lets one event through per period', () async {
    var t = DateTime(2026, 9, 14, 12);
    final ctl = StreamController<int>();
    final out = <int>[];
    final sub = throttle(ctl.stream, const Duration(milliseconds: 66), now: () => t).listen(out.add);
    for (var i = 0; i < 5; i++) {
      ctl.add(i); // all "at once"
    }
    await Future<void>.delayed(Duration.zero);
    t = t.add(const Duration(milliseconds: 70));
    ctl.add(5);
    await Future<void>.delayed(Duration.zero);
    expect(out, [0, 5]);
    await sub.cancel();
  });
}
