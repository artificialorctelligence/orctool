import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'location_service.dart';

class LocationInstrument extends Instrument {
  LocationInstrument(this._svc);
  final LocationService _svc;

  @override
  String get id => 'location';
  @override
  String get name => 'Location';

  /// iOS stays false until an "Always" authorisation flow exists (spec §4).
  @override
  bool get canLog => Platform.isAndroid;

  @override
  Duration get sampleTimeout => const Duration(seconds: 60);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<Reading> live() => _svc.stream().map(_reading);

  @override
  Future<Reading> sample() async => _reading(await _svc.current(accuracy: _accuracy(log), timeLimit: const Duration(seconds: 45)));

  @override
  LogSettings get defaultLogSettings => const LogSettings(extra: {'accuracy': 'high'});

  LocationAccuracy _accuracy(LogSettings s) => s.extra['accuracy'] == 'low' ? LocationAccuracy.low : LocationAccuracy.high;

  Reading _reading(Position p) => Reading(p.timestamp, {'lat': p.latitude, 'lon': p.longitude, 'alt': p.altitude, 'acc': p.accuracy, 'speed': p.speed});

  @override
  Future<String?> logPrecondition() async => await _svc.hasBackground() ? null : 'Location must be allowed "all the time" — open Details';

  @override
  String logSummary(LogSettings s) => 'Log: ${s.interval.label} · ${s.extra['accuracy'] ?? 'high'}';

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.headlineMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    if (r == null) return Text('—', style: big);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${r.values['lat']!.toStringAsFixed(5)}, ${r.values['lon']!.toStringAsFixed(5)}', style: big),
      const SizedBox(height: 8),
      Text('${r.values['alt']!.toStringAsFixed(0)} m ${orc.text('altitude')}', style: big.copyWith(fontSize: big.fontSize! * 0.8)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Accuracy': r == null ? '—' : '±${r.values['acc']!.toStringAsFixed(0)} m',
        'Speed': r == null ? '—' : '${r.values['speed']!.toStringAsFixed(1)} m/s',
        'Fix at': r == null ? '—' : TimeOfDay.fromDateTime(r.ts.toLocal()).format(context),
      });

  @override
  Widget buildError(BuildContext context, Object error, VoidCallback retry) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$error', textAlign: TextAlign.center),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: retry, child: const Text('Retry')),
          TextButton(onPressed: _svc.openSettings, child: const Text('App settings')),
        ]),
      ]);

  /// The prominent disclosure Play requires before the system prompt (spec §4).
  @override
  Widget buildLogSettings(BuildContext context, LogSettings current, ValueChanged<LogSettings> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: current.extra['accuracy'] as String? ?? 'high',
        decoration: const InputDecoration(labelText: 'Accuracy'),
        items: const [DropdownMenuItem(value: 'high', child: Text('High (GPS)')), DropdownMenuItem(value: 'low', child: Text('Low (network)'))],
        onChanged: (v) => onChanged(current.copyWith(extra: {...current.extra, 'accuracy': v})),
      ),
      const SizedBox(height: 16),
      const Text('Logging location while the app is closed needs location access "all the time". '
          'Orctool records your position on the schedule above, keeps it only on this phone, and never sends it anywhere.'),
      const SizedBox(height: 8),
      _BackgroundPermissionButton(_svc),
    ]);
  }
}

/// "All the time" is granted in the system Settings page on Android 11+, so the
/// answer can only be learned when the app comes back to the foreground.
class _BackgroundPermissionButton extends StatefulWidget {
  const _BackgroundPermissionButton(this.svc);
  final LocationService svc;

  @override
  State<_BackgroundPermissionButton> createState() => _BackgroundPermissionButtonState();
}

class _BackgroundPermissionButtonState extends State<_BackgroundPermissionButton> with WidgetsBindingObserver {
  late Future<bool> _granted = widget.svc.hasBackground();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() => setState(() {
        _granted = widget.svc.hasBackground();
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
        future: _granted,
        builder: (context, snap) => FilledButton(
          onPressed: snap.data == true
              ? null
              : () async {
                  await widget.svc.requestBackground();
                  _refresh();
                },
          child: Text(snap.data == true ? 'Allowed all the time' : 'Allow all the time'),
        ),
      );
}
