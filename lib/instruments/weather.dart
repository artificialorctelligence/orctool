import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'location_service.dart';

const _fields = 'temperature_2m,relative_humidity_2m,surface_pressure,wind_speed_10m,wind_direction_10m,weather_code';

String describeWmo(int code) => switch (code) {
      0 => 'Clear',
      1 => 'Mostly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      >= 51 && <= 57 => 'Drizzle',
      >= 61 && <= 67 => 'Rain',
      >= 71 && <= 77 => 'Snow',
      >= 80 && <= 82 => 'Showers',
      85 || 86 => 'Snow showers',
      >= 95 && <= 99 => 'Thunderstorm',
      _ => 'Code $code',
    };

/// Open-Meteo, no key. Sends the phone's approximate position (spec §4).
class WeatherInstrument extends Instrument {
  WeatherInstrument(this._loc, {http.Client? client, this.refresh = const Duration(minutes: 15)}) : _client = client ?? http.Client();
  final LocationService _loc;
  final http.Client _client;
  final Duration refresh;

  @override
  String get id => 'weather';
  @override
  String get name => 'Weather';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Reading> sample() async {
    final p = await _loc.current(accuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 20));
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {'latitude': '${p.latitude}', 'longitude': '${p.longitude}', 'current': _fields});
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Weather service returned ${res.statusCode}');
    final cur = ((jsonDecode(res.body) as Map)['current'] as Map).cast<String, Object?>();
    return Reading(DateTime.now(), {
      'temp': cur['temperature_2m'] as num,
      'humidity': cur['relative_humidity_2m'] as num,
      'pressure': cur['surface_pressure'] as num,
      'wind': cur['wind_speed_10m'] as num,
      'wind_dir': cur['wind_direction_10m'] as num,
      'code': cur['weather_code'] as num,
      'lat': p.latitude,
      'lon': p.longitude,
    });
  }

  /// First fetch, then every [refresh]; a failed refresh re-emits the last reading (its age shows).
  @override
  Stream<Reading> live() async* {
    Reading last = await sample();
    yield last;
    await for (final _ in Stream<void>.periodic(refresh)) {
      try {
        last = await sample();
      } catch (_) {
        // Spec §5: show the last reading with its age rather than an error.
      }
      yield last;
    }
  }

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    if (r == null) return Text('—', style: big);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${r.values['temp']!.toStringAsFixed(1)} °C', style: big),
      Text(orc.text(describeWmo(r.values['code']!.toInt())), style: TextStyle(color: orc.accent, fontFamily: orc.displayFont, fontSize: 18)),
      Text('${orc.text('as of')} ${TimeOfDay.fromDateTime(r.ts.toLocal()).format(context)}', style: TextStyle(color: orc.accent.withValues(alpha: 0.6), fontFamily: orc.displayFont)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Humidity': r == null ? '—' : '${r.values['humidity']} %',
        'Pressure': r == null ? '—' : '${r.values['pressure']} hPa',
        'Wind': r == null ? '—' : '${r.values['wind']} km/h @ ${r.values['wind_dir']}°',
      });
}
