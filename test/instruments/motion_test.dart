import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/motion.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('tilt: flat is 0/0; tipped onto its right edge is roll 90', () {
    final flat = tilt(0, 0, 9.81);
    expect(flat.pitch, closeTo(0, 0.01));
    expect(flat.roll, closeTo(0, 0.01));
    expect(tilt(-9.81, 0, 0).roll, closeTo(-90, 0.01));
    expect(tilt(0, 9.81, 0).pitch, closeTo(90, 0.01));
  });

  test('live readings carry g, tilt and the latest gyro; sample is the first reading', () async {
    final accel = StreamController<AccelerometerEvent>();
    final gyro = StreamController<GyroscopeEvent>();
    final m = MotionInstrument(accel: accel.stream, gyro: gyro.stream);
    final first = m.live().first;
    gyro.add(GyroscopeEvent(0.1, 0.2, 0.3, DateTime(2026)));
    accel.add(AccelerometerEvent(0, 0, 9.80665, DateTime(2026)));
    final r = await first;
    expect(r.values['g'], closeTo(1.0, 0.001));
    expect(r.values['gz'], 0.3);
    expect(r.values['pitch'], closeTo(0, 0.01));
    expect(m.canLog, isTrue);
    expect(m.id, 'motion');
  });
}
