import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'sensor_util.dart';

/// Android's getRotationMatrix + getOrientation, reduced to the azimuth:
/// H = E × A (east), M = A × H (north), of which only My is needed; azimuth = atan2(Hy, My).
double headingDegrees({required double ax, required double ay, required double az, required double mx, required double my, required double mz}) {
  var hx = my * az - mz * ay, hy = mz * ax - mx * az, hz = mx * ay - my * ax;
  final hn = sqrt(hx * hx + hy * hy + hz * hz);
  if (hn == 0) return 0;
  hx /= hn; hy /= hn; hz /= hn;
  final an = sqrt(ax * ax + ay * ay + az * az);
  final nx = ax / an, nz = az / an;
  final my_ = nz * hx - nx * hz; // M = A × H, y component
  final deg = atan2(hy, my_) * 180 / pi;
  return (deg + 360) % 360;
}

const _points = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
String cardinal(double deg) => _points[((deg + 11.25) % 360 ~/ 22.5)];

class CompassInstrument extends Instrument {
  CompassInstrument({Stream<AccelerometerEvent>? accel, Stream<MagnetometerEvent>? mag})
      : _accel = accel ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
        _mag = mag ?? magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval);

  final Stream<AccelerometerEvent> _accel;
  final Stream<MagnetometerEvent> _mag;

  @override
  String get id => 'compass';
  @override
  String get name => 'Compass';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() => firstEventWithin(_mag, const Duration(seconds: 2));

  @override
  Stream<Reading> live() => merge2(_accel, _mag).map((e) {
        final (a, m) = e;
        return Reading(DateTime.now(), {
          'heading': headingDegrees(ax: a.x, ay: a.y, az: a.z, mx: m.x, my: m.y, mz: m.z),
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
