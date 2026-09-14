import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/instruments/location.dart';
import 'package:orctool/instruments/location_service.dart';
import 'package:orctool/skins/all.dart';

class FakeLocation extends LocationService {
  FakeLocation({this.permitted = true, this.background = false});
  bool permitted, background;
  static final pos = Position(latitude: 51.5, longitude: -0.12, timestamp: DateTime(2026, 9, 13), accuracy: 5, altitude: 312, altitudeAccuracy: 3, heading: 0, headingAccuracy: 0, speed: 1.2, speedAccuracy: 0.5);

  @override
  Future<void> ensurePermission() async {
    if (!permitted) throw LocationDenied('Location permission needed');
  }
  @override
  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    await ensurePermission();
    return pos;
  }
  @override
  Stream<Position> stream() async* {
    await ensurePermission();
    yield pos;
  }
  @override
  Future<bool> hasBackground() async => background;
}

void main() {
  test('reading columns', () async {
    final r = await LocationInstrument(FakeLocation()).sample();
    expect(r.values, {'lat': 51.5, 'lon': -0.12, 'alt': 312, 'acc': 5, 'speed': 1.2});
    expect(r.ts, DateTime(2026, 9, 13));
  });

  test('live surfaces the denial as a stream error', () {
    expect(LocationInstrument(FakeLocation(permitted: false)).live().first, throwsA(isA<LocationDenied>()));
  });

  test('logPrecondition needs background permission', () async {
    expect(await LocationInstrument(FakeLocation(background: false)).logPrecondition(), contains('all the time'));
    expect(await LocationInstrument(FakeLocation(background: true)).logPrecondition(), isNull);
  });

  testWidgets('error band offers Retry and App settings', (t) async {
    var retried = false;
    final i = LocationInstrument(FakeLocation());
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: Builder(builder: (c) => i.buildError(c, LocationDenied('Location permission needed'), () => retried = true)))));
    expect(find.text('Location permission needed'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  test('default log settings are hourly with high accuracy; sample honours a low setting', () async {
    final i = LocationInstrument(FakeLocation());
    expect(i.defaultLogSettings.interval, LogInterval.hourly);
    expect(i.defaultLogSettings.extra['accuracy'], 'high');
    final seen = <LocationAccuracy>[];
    final svc = _RecordingLocation(seen);
    final j = LocationInstrument(svc);
    j.log = const LogSettings(extra: {'accuracy': 'low'});
    await j.sample();
    expect(seen, [LocationAccuracy.low]);
  });
}

class _RecordingLocation extends FakeLocation {
  _RecordingLocation(this.seen);
  final List<LocationAccuracy> seen;
  @override
  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    seen.add(accuracy);
    return FakeLocation.pos;
  }
}
