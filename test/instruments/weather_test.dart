import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orctool/instruments/weather.dart';

import 'location_test.dart' show FakeLocation;

const _body = '{"latitude":51.49,"longitude":-0.13,"current_units":{"temperature_2m":"°C"},'
    '"current":{"time":"2026-09-14T02:15","interval":900,"temperature_2m":19.3,"relative_humidity_2m":94,'
    '"surface_pressure":1022.3,"wind_speed_10m":7.9,"wind_direction_10m":235,"weather_code":3}}';

void main() {
  test('sample asks Open-Meteo for the current conditions at the phone position', () async {
    Uri? seen;
    final client = MockClient((req) async {
      seen = req.url;
      return http.Response(_body, 200);
    });
    final r = await WeatherInstrument(FakeLocation(), client: client).sample();
    expect(seen!.host, 'api.open-meteo.com');
    expect(seen!.queryParameters['latitude'], '51.5');
    expect(seen!.queryParameters['current'], contains('temperature_2m'));
    expect(r.values['temp'], 19.3);
    expect(r.values['humidity'], 94);
    expect(r.values['pressure'], 1022.3);
    expect(r.values['wind'], 7.9);
    expect(r.values['wind_dir'], 235);
    expect(r.values['code'], 3);
    expect(r.values['lat'], 51.5);
  });

  test('a non-200 or malformed response is an error, not a reading', () {
    final bad = MockClient((_) async => http.Response('nope', 503));
    expect(WeatherInstrument(FakeLocation(), client: bad).sample(), throwsException);
    final junk = MockClient((_) async => http.Response(jsonEncode({'x': 1}), 200));
    expect(WeatherInstrument(FakeLocation(), client: junk).sample(), throwsA(anything));
  });

  test('live keeps the last reading when a refresh fails', () async {
    var calls = 0;
    final client = MockClient((_) async => ++calls == 1 ? http.Response(_body, 200) : http.Response('', 500));
    final w = WeatherInstrument(FakeLocation(), client: client, refresh: const Duration(milliseconds: 10));
    final two = await w.live().take(2).toList();
    expect(two[1].values['temp'], 19.3);
    expect(two[1].ts, two[0].ts, reason: 'age is visible: the timestamp did not move');
  });

  test('describeWmo', () {
    expect(describeWmo(0), 'Clear');
    expect(describeWmo(3), 'Overcast');
    expect(describeWmo(61), 'Rain');
    expect(describeWmo(95), 'Thunderstorm');
    expect(describeWmo(42), 'Code 42');
  });
}
