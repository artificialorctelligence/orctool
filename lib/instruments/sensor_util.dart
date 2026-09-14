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
