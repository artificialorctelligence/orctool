import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/settings_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

class Blocked extends FakeInstrument {
  Blocked() : super(id: 'blocked', name: 'Blocked');
  @override
  Future<String?> logPrecondition() async => 'Needs a permission first';
}

void main() {
  late Registry reg;
  late SpyScheduler sched;

  setUp(() async {
    sched = SpyScheduler();
    reg = Registry([FakeInstrument(id: 'a', name: 'Alpha'), FakeInstrument(id: 'b', name: 'Beta', canLog: false), Blocked()], await memoryPrefs(), sched);
    await reg.probe();
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: SettingsScreen(prefs: reg.prefs, registry: reg))));
    await t.pumpAndSettle();
  }

  testWidgets('skin, retention and cap persist', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('skin')));
    await t.pumpAndSettle();
    await t.tap(find.text('Console').last);
    await t.pumpAndSettle();
    expect(reg.prefs.skinId, 'console');
    await t.tap(find.byKey(const Key('retention')));
    await t.pumpAndSettle();
    await t.tap(find.text('90 days').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cap')));
    await t.pumpAndSettle();
    await t.tap(find.text('200 MB').last);
    await t.pumpAndSettle();
    expect(reg.prefs.limits.retentionDays, 90);
    expect(reg.prefs.limits.capBytes, 200 * 1024 * 1024);
  });

  testWidgets('Instruments: show toggle, log toggle only when canLog, precondition blocks logging', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('log-a')), findsOneWidget);
    expect(find.byKey(const Key('log-b')), findsNothing);
    await t.tap(find.byKey(const Key('show-b')));
    await t.pumpAndSettle();
    expect(reg.isShown('b'), isFalse);
    await t.tap(find.byKey(const Key('log-a')));
    await t.pumpAndSettle();
    expect(reg.isLogging('a'), isTrue);
    expect(sched.calls, ['schedule a 60']);
    await t.tap(find.byKey(const Key('log-blocked')));
    await t.pumpAndSettle();
    expect(reg.isLogging('blocked'), isFalse);
    expect(find.text('Needs a permission first'), findsOneWidget);
  });

  testWidgets('details page sets the interval', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('interval')));
    await t.pumpAndSettle();
    await t.tap(find.text('daily').last);
    await t.pumpAndSettle();
    expect(reg.settingsFor(reg.byId('a')!).interval, LogInterval.daily);
  });
}
