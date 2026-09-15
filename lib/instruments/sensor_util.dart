import 'dart:async';

/// The availability probe for stream-based sensors: does anything arrive at all?
Future<bool> firstEventWithin<T>(Stream<T> s, Duration d) async {
  try {
    await s.first.timeout(d);
    return true;
  } catch (_) {
    // Timeout or a plugin error both mean "not here".
    return false;
  }
}

/// Drops events that arrive sooner than [every] after the last one let through.
/// Phones deliver sensor events far faster than the requested sampling period
/// (a Pixel 9 gives ~100 Hz for a 15 Hz request); the screen and a session both
/// want the display rate, not the hardware rate.
Stream<T> throttle<T>(Stream<T> s, Duration every, {DateTime Function() now = DateTime.now}) {
  DateTime? last;
  return s.where((_) {
    final t = now();
    if (last != null && t.difference(last!) < every) return false;
    last = t;
    return true;
  });
}

/// Emits (a, latestB) on every `a` event once `b` has produced something.
Stream<(A, B)> merge2<A, B>(Stream<A> a, Stream<B> b) {
  late StreamController<(A, B)> ctl;
  StreamSubscription<A>? sa;
  StreamSubscription<B>? sb;
  B? latest;
  var hasB = false;
  ctl = StreamController<(A, B)>(
    onListen: () {
      sb = b.listen((v) {
        latest = v;
        hasB = true;
      }, onError: ctl.addError);
      sa = a.listen((v) {
        if (hasB) ctl.add((v, latest as B));
      }, onError: ctl.addError, onDone: ctl.close);
    },
    onCancel: () async {
      await sa?.cancel();
      await sb?.cancel();
    },
  );
  return ctl.stream;
}
