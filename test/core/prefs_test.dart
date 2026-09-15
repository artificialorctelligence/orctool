import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/prefs.dart';
import 'package:orctool/core/store.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Prefs p;
  setUp(() async => p = await memoryPrefs());

  test('defaults', () {
    expect(p.railOut, isTrue);
    expect(p.skinId, 'plain');
    expect(p.limits.retentionDays, 30);
    expect(p.limits.capBytes, 50 * 1024 * 1024);
    expect(p.order, isEmpty);
    expect(p.hidden, isEmpty);
    expect(p.logging, isEmpty);
    expect(p.logSettings('x'), isNull);
    expect(p.logRun('x'), isNull);
  });

  test('every setter persists, and notifies', () async {
    var notified = 0;
    p.addListener(() => notified++);
    await p.setRailOut(false);
    await p.setSkinId('console');
    await p.setLimits(const Limits(retentionDays: 7, capBytes: 10));
    await p.setOrder(['b', 'a']);
    await p.setHidden('a', true);
    await p.setLogging('b', true);
    await p.setLogSettings('b', const LogSettings(interval: LogInterval.daily, extra: {'k': 1}));
    await p.setLogRun('b', 'run-1');
    final q = await Prefs.open(); // same in-memory platform instance
    expect(q.railOut, isFalse);
    expect(q.skinId, 'console');
    expect(q.limits.retentionDays, 7);
    expect(q.limits.capBytes, 10);
    expect(q.order, ['b', 'a']);
    expect(q.hidden, {'a'});
    expect(q.logging, {'b'});
    expect(q.logSettings('b')!.interval, LogInterval.daily);
    expect(q.logSettings('b')!.extra, {'k': 1});
    expect(q.logRun('b'), 'run-1');
    expect(notified, 8);
    await p.setHidden('a', false);
    await p.setLogging('b', false);
    await p.setLogRun('b', null);
    expect(p.hidden, isEmpty);
    expect(p.logging, isEmpty);
    expect(p.logRun('b'), isNull);
  });

  test('setLastFix persists silently: no notify, readable from a fresh open', () async {
    var notified = 0;
    p.addListener(() => notified++);
    expect(p.lastFix, isNull);
    await p.setLastFix(51.5, -0.12);
    expect(notified, 0, reason: 'a 1 Hz fix must not rebuild listeners');
    final q = await Prefs.open(); // same in-memory platform instance
    expect(q.lastFix, (lat: 51.5, lon: -0.12));
  });
}
