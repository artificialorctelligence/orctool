import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';

import '../fakes.dart';

void main() {
  test('LogSettings round-trips through JSON including extra', () {
    const s = LogSettings(interval: LogInterval.daily, extra: {'accuracy': 'high'});
    final back = LogSettings.fromJson(s.toJson());
    expect(back.interval, LogInterval.daily);
    expect(back.extra, {'accuracy': 'high'});
  });

  test('LogSettings.fromJson tolerates a missing interval', () {
    expect(LogSettings.fromJson(const {}).interval, LogInterval.hourly);
  });

  test('default toRow is the reading values and logSummary names the interval', () {
    final i = FakeInstrument();
    final r = Reading(DateTime(2026, 9, 13), const {'x': 1.5});
    expect(i.toRow(r), {'x': 1.5});
    expect(i.toRow(Reading(DateTime(2026), const {'d': 51.231496247, 'n': 3})), {'d': 51.2315, 'n': 3});
    expect(i.logSummary(const LogSettings(interval: LogInterval.m15)), 'Log: 15 min');
    expect(i.logPrecondition(), completion(isNull));
  });

  test('log falls back to defaultLogSettings until set', () {
    final i = FakeInstrument();
    expect(i.log.interval, LogInterval.hourly);
    i.log = const LogSettings(interval: LogInterval.daily);
    expect(i.log.interval, LogInterval.daily);
  });
}
