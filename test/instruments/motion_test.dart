import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/motion.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  test('tilt: flat is 0/0; right edge down is roll -90; nose up is pitch 90', () {
    final flat = tilt(0, 0, 9.81);
    expect(flat.pitch, closeTo(0, 0.01));
    expect(flat.roll, closeTo(0, 0.01));
    expect(tilt(-9.81, 0, 0).roll, closeTo(-90, 0.01));
    expect(tilt(0, 9.81, 0).pitch, closeTo(90, 0.01));
  });

  test('bubble goes to the high side: right edge down → left; nose up → up', () {
    final rightDown = bubbleOffset(pitch: 0, roll: -10, radius: 90);
    expect(rightDown.dx, lessThan(0));
    expect(rightDown.dy, closeTo(0, 1e-9));
    final noseUp = bubbleOffset(pitch: 10, roll: 0, radius: 90);
    expect(noseUp.dy, lessThan(0));
    expect(bubbleOffset(pitch: 90, roll: 0, radius: 90).dy, -90, reason: 'clamped to the ring');
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
