import 'dart:async';
import 'dart:math';

import 'package:flutter_rotation_sensor/flutter_rotation_sensor.dart' as rs;
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// A device rotated [deg] about the vertical axis, with the given accuracy in radians.
rs.OrientationEvent turned(double deg, {double accuracy = -1}) {
  final h = deg * pi / 360; // half angle
  return rs.OrientationEvent(quaternion: rs.Quaternion(0, 0, sin(h), cos(h)), accuracy: accuracy, timestamp: 0);
}

void main() {
  test('cardinal', () {
    expect(cardinal(0), 'N');
    expect(cardinal(247), 'WSW');
    expect(cardinal(359), 'N');
  });

  test('heading is the platform azimuth in degrees 0–360; accuracy in degrees or -1', () async {
    final orient = StreamController<rs.OrientationEvent>();
    final mag = StreamController<MagnetometerEvent>();
    final c = CompassInstrument(orientation: orient.stream, mag: mag.stream);
    final first = c.live().first;
    mag.add(MagnetometerEvent(0, 30, -40, DateTime(2026)));
    final ev = turned(90, accuracy: 0.1);
    orient.add(ev);
    final r = await first;
    expect(r.values['heading'], closeTo((ev.eulerAngles.azimuth * 180 / pi + 360) % 360, 1e-6));
    expect(r.values['heading'], inInclusiveRange(0, 360));
    expect(r.values['accuracy'], closeTo(0.1 * 180 / pi, 1e-6));
    expect(r.values['field'], closeTo(50, 0.01));
    expect(c.id, 'compass');
  });

  test('a rotation about the vertical axis changes the heading by that angle', () {
    final a = turned(0).eulerAngles.azimuth, b = turned(90).eulerAngles.azimuth;
    final d = ((b - a) * 180 / pi) % 360; // azimuth runs clockwise; the quaternion turns anticlockwise
    expect(min(d, 360 - d), closeTo(90, 1e-6));
  });

  test('no reported accuracy stays -1', () async {
    final orient = StreamController<rs.OrientationEvent>();
    final mag = StreamController<MagnetometerEvent>();
    final c = CompassInstrument(orientation: orient.stream, mag: mag.stream);
    final first = c.live().first;
    mag.add(MagnetometerEvent(0, 30, -40, DateTime(2026)));
    orient.add(turned(10));
    expect((await first).values['accuracy'], -1);
  });
}
