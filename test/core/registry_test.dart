import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/registry.dart';

import '../fakes.dart';

class SpyScheduler implements Scheduler {
  final calls = <String>[];
  @override
  Future<void> schedule(String id, Duration every) async => calls.add('schedule $id ${every.inMinutes}');
  @override
  Future<void> cancel(String id) async => calls.add('cancel $id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SpyScheduler sched;
  late FakeInstrument a, b, gone, noLog;
  late Registry reg;

  setUp(() async {
    sched = SpyScheduler();
    a = FakeInstrument(id: 'a');
    b = FakeInstrument(id: 'b');
    gone = FakeInstrument(id: 'gone', available: false);
    noLog = FakeInstrument(id: 'nolog', canLog: false);
    reg = Registry([a, gone, b, noLog], await memoryPrefs(), sched);
    await reg.probe();
  });

  test('probe drops unavailable instruments and keeps registration order', () {
    expect(reg.available.map((i) => i.id), ['a', 'b', 'nolog']);
    expect(reg.byId('gone'), isNull);
  });

  test('reorder persists and rail follows it; hidden leaves the rail but not the list', () async {
    await reg.reorder(0, 3); // a to the end
    expect(reg.ordered.map((i) => i.id), ['b', 'nolog', 'a']);
    await reg.setShown('nolog', false);
    expect(reg.rail.map((i) => i.id), ['b', 'a']);
    expect(reg.ordered.map((i) => i.id), ['b', 'nolog', 'a']);
    expect(reg.isShown('nolog'), isFalse);
  });

  test('logging on schedules with the interval, starts a run, and off cancels', () async {
    await reg.setLogSettings(a, const LogSettings(interval: LogInterval.daily));
    await reg.setLogging(a, true);
    expect(reg.isLogging('a'), isTrue);
    expect(reg.prefs.logRun('a'), isNotNull);
    expect(sched.calls, ['schedule a 1440']);
    await reg.setLogSettings(a, const LogSettings(interval: LogInterval.m15));
    expect(sched.calls.last, 'schedule a 15');
    await reg.setLogging(a, false);
    expect(sched.calls.last, 'cancel a');
    expect(reg.prefs.logRun('a'), isNull);
  });

  test('settingsFor falls back to the instrument default', () {
    expect(reg.settingsFor(b).interval, LogInterval.hourly);
  });

  test('logging an instrument that cannot log is an error', () {
    expect(() => reg.setLogging(noLog, true), throwsArgumentError);
  });
}
