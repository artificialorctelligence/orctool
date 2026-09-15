import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart' as rs;
import 'package:sensors_plus/sensors_plus.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'sensor_util.dart';

const _points = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
String cardinal(double deg) => _points[((deg + 11.25) % 360 ~/ 22.5)];

/// Heading from the platform's fused rotation-vector sensor (gyro-stabilised,
/// OS-calibrated). Slice 1 first derived it from the raw magnetometer and
/// accelerometer; on a Pixel 9 that wandered ~9° at rest, and smoothing did not
/// help because the wander is slow (a calibration/environment effect, not noise).
/// The magnetometer stays for field strength.
class CompassInstrument extends Instrument {
  CompassInstrument({Stream<rs.OrientationEvent>? orientation, Stream<MagnetometerEvent>? mag})
      : _orientation = orientation ?? _platformOrientation(),
        _mag = mag ?? magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval);

  static Stream<rs.OrientationEvent> _platformOrientation() {
    rs.RotationSensor.samplingPeriod = SensorInterval.uiInterval;
    rs.RotationSensor.referenceFrame = rs.ReferenceFrame.magneticNorth;
    return rs.RotationSensor.orientationStream;
  }

  final Stream<rs.OrientationEvent> _orientation;
  final Stream<MagnetometerEvent> _mag;

  @override
  String get id => 'compass';
  @override
  String get name => 'Compass';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() => firstEventWithin(_orientation, const Duration(seconds: 2));

  /// `accuracy` is degrees, or -1 when the platform does not report one.
  @override
  Stream<Reading> live() => throttle(merge2(_orientation, _mag), SensorInterval.uiInterval).map((e) {
        final (o, m) = e;
        return Reading(DateTime.now(), {
          'heading': (o.eulerAngles.azimuth * 180 / pi + 360) % 360,
          'accuracy': o.accuracy < 0 ? -1 : o.accuracy * 180 / pi,
          'field': sqrt(m.x * m.x + m.y * m.y + m.z * m.z),
          'mx': m.x, 'my': m.y, 'mz': m.z,
        });
      });

  @override
  Future<Reading> sample() => live().first;

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final h = r?.values['heading']?.toDouble();
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 180, height: 180, child: CustomPaint(painter: _DialPainter(heading: h ?? 0, accent: orc.accent, ring: orc.panel))),
      const SizedBox(height: 12),
      Text(h == null ? '—' : '${h.round()}°', style: big),
      Text(h == null ? '' : '${cardinal(h)} · ${orc.text('magnetic')}', style: TextStyle(color: orc.accent, fontFamily: orc.displayFont)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Field': r == null ? '—' : '${r.values['field']!.toStringAsFixed(1)} µT',
        'Accuracy': r == null || r.values['accuracy']! < 0 ? '—' : '±${r.values['accuracy']!.toStringAsFixed(0)}°',
        'X Y Z': r == null ? '—' : '${r.values['mx']!.toStringAsFixed(1)} ${r.values['my']!.toStringAsFixed(1)} ${r.values['mz']!.toStringAsFixed(1)}',
      });
}

/// A rose that rotates so magnetic north stays north; the fixed lubber line is up.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.accent, required this.ring});
  final double heading;
  final Color accent, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * pi / 180);
    final tick = Paint()..color = ring..strokeWidth = 2;
    for (var i = 0; i < 36; i++) {
      final len = i % 9 == 0 ? 16.0 : 8.0;
      canvas.drawLine(Offset(0, -r), Offset(0, -r + len), i == 0 ? (Paint()..color = accent..strokeWidth = 4) : tick);
      canvas.rotate(pi / 18);
    }
    canvas.restore();
    canvas.drawLine(Offset(c.dx, c.dy - r - 2), Offset(c.dx, c.dy - r + 24), Paint()..color = accent..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.heading != heading || o.accent != accent || o.ring != ring;
}
