import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'sensor_util.dart';

const _g0 = 9.80665;

/// Pitch (nose up, +) and roll (right side down, +) in degrees from gravity.
({double pitch, double roll}) tilt(double ax, double ay, double az) => (
      pitch: atan2(ay, sqrt(ax * ax + az * az)) * 180 / pi,
      roll: atan2(ax, az) * 180 / pi,
    );

/// Where the bubble sits for a tilt: toward the HIGH side, clamped to the ring.
/// Roll < 0 is right-edge-down (Android's accelerometer sign), so dx = +roll;
/// pitch > 0 is nose-up, so dy = −pitch (screen y points down).
Offset bubbleOffset({required double pitch, required double roll, required double radius}) {
  final scale = radius / 45; // 45° reaches the ring
  return Offset((roll * scale).clamp(-radius, radius), (-pitch * scale).clamp(-radius, radius));
}

class MotionInstrument extends Instrument {
  MotionInstrument({Stream<AccelerometerEvent>? accel, Stream<GyroscopeEvent>? gyro})
      : _accel = accel ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
        _gyro = gyro ?? gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval);

  final Stream<AccelerometerEvent> _accel;
  final Stream<GyroscopeEvent> _gyro;

  @override
  String get id => 'motion';
  @override
  String get name => 'Motion';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() => firstEventWithin(_accel, const Duration(seconds: 2));

  @override
  Stream<Reading> live() => merge2(_accel, _gyro).map((e) {
        final (a, w) = e;
        final t = tilt(a.x, a.y, a.z);
        return Reading(DateTime.now(), {
          'ax': a.x, 'ay': a.y, 'az': a.z,
          'gx': w.x, 'gy': w.y, 'gz': w.z,
          'g': sqrt(a.x * a.x + a.y * a.y + a.z * a.z) / _g0,
          'pitch': t.pitch, 'roll': t.roll,
        });
      });

  @override
  Future<Reading> sample() => live().first;

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 160,
        height: 160,
        child: CustomPaint(painter: _LevelPainter(pitch: r?.values['pitch']?.toDouble() ?? 0, roll: r?.values['roll']?.toDouble() ?? 0, accent: orc.accent, ring: orc.panel)),
      ),
      const SizedBox(height: 12),
      Text(r == null ? '—' : '${r.values['g']!.toStringAsFixed(3)} g', style: big),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Pitch': _deg(r?.values['pitch']),
        'Roll': _deg(r?.values['roll']),
        'Accel': _xyz(r, 'ax', 'ay', 'az', 'm/s²'),
        'Gyro': _xyz(r, 'gx', 'gy', 'gz', 'rad/s'),
      });

  String _deg(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';
  String _xyz(Reading? r, String x, String y, String z, String unit) =>
      r == null ? '—' : '${r.values[x]!.toStringAsFixed(2)} ${r.values[y]!.toStringAsFixed(2)} ${r.values[z]!.toStringAsFixed(2)} $unit';
}

/// A bubble level: the bubble moves to the high side, clamped to the ring.
class _LevelPainter extends CustomPainter {
  _LevelPainter({required this.pitch, required this.roll, required this.accent, required this.ring});
  final double pitch, roll;
  final Color accent, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rr = size.width / 2 - 4;
    canvas.drawCircle(c, rr, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(c, 10, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 1);
    final off = bubbleOffset(pitch: pitch, roll: roll, radius: rr);
    canvas.drawCircle(c + off, 12, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.pitch != pitch || o.roll != roll || o.accent != accent || o.ring != ring;
}
