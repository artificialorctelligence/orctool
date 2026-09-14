import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  // Phone flat (gravity on +z). Earth's field: horizontal component plus a
  // downward component; the horizontal part points to magnetic north.
  test('heading: north along +y is 0°, north along +x is 270°, along -y is 180°', () {
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 0, my: 20, mz: -40), closeTo(0, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 20, my: 0, mz: -40), closeTo(270, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 0, my: -20, mz: -40), closeTo(180, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: -20, my: 0, mz: -40), closeTo(90, 0.01));
  });

  test('heading is tilt-compensated: pitching the phone up does not change it', () {
    final flat = headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 14.1, my: 14.1, mz: -40);
    // Rotate both vectors about x by 30°: (x, y, z) → (x, y·c − z·s, y·s + z·c).
    const c = 0.8660254, s = 0.5;
    final tilted = headingDegrees(ax: 0, ay: -9.8 * s, az: 9.8 * c, mx: 14.1, my: 14.1 * c + 40 * s, mz: 14.1 * s - 40 * c);
    expect(tilted, closeTo(flat, 0.5));
  });

  test('cardinal', () {
    expect(cardinal(0), 'N');
    expect(cardinal(247), 'WSW');
    expect(cardinal(359), 'N');
  });

  test('live reading carries heading and field strength in µT', () async {
    final accel = StreamController<AccelerometerEvent>();
    final mag = StreamController<MagnetometerEvent>();
    final c = CompassInstrument(accel: accel.stream, mag: mag.stream);
    final first = c.live().first;
    accel.add(AccelerometerEvent(0, 0, 9.8, DateTime(2026)));
    mag.add(MagnetometerEvent(0, 30, -40, DateTime(2026)));
    accel.add(AccelerometerEvent(0, 0, 9.8, DateTime(2026)));
    final r = await first;
    expect(r.values['heading'], closeTo(0, 0.01));
    expect(r.values['field'], closeTo(50, 0.01));
    expect(c.id, 'compass');
  });
}
