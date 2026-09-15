import 'dart:async';
import 'dart:math';

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
  smootherTests();
}

void smootherTests() {
  test('HeadingSmoother converges to a constant input and averages across north correctly', () {
    final s = HeadingSmoother();
    double h = 0;
    for (var i = 0; i < 40; i++) {
      h = s.add(90);
    }
    expect(h, closeTo(90, 0.01));
    final n = HeadingSmoother(alpha: 0.5);
    n.add(359);
    expect(n.add(1), closeTo(0, 0.01), reason: 'wraps through north, not through 180');
  });

  test('a jittering input is steadier after smoothing', () {
    final s = HeadingSmoother();
    final raw = [50.0, 56.0, 45.0, 55.0, 47.0, 53.0, 46.0, 54.0, 49.0, 51.0];
    final smoothed = raw.map(s.add).toList();
    double spread(List<double> xs) => xs.reduce(max) - xs.reduce(min);
    expect(spread(smoothed.sublist(5)), lessThan(spread(raw.sublist(5)) / 2));
  });
}
