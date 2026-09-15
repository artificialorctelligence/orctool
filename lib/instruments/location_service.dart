import 'package:geolocator/geolocator.dart';

import '../core/prefs.dart';

class LocationDenied implements Exception {
  LocationDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The one place geolocator is called. Location and Weather share it.
class LocationService {
  LocationService({this.prefs});
  final Prefs? prefs;

  /// The last position any foreground fix delivered; a background sample's fallback.
  ({double lat, double lon})? get lastFix => prefs?.lastFix;

  void _remember(Position p) => prefs?.setLastFix(p.latitude, p.longitude);

  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw LocationDenied('Location is turned off on this phone');
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.deniedForever) throw LocationDenied('Location permission denied permanently — use App settings');
    if (p == LocationPermission.denied) throw LocationDenied('Location permission needed');
  }

  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    await ensurePermission();
    final p = await Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeLimit));
    _remember(p);
    return p;
  }

  Stream<Position> stream() async* {
    await ensurePermission();
    yield* Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best)).map((p) {
      _remember(p);
      return p;
    });
  }

  Future<bool> hasBackground() async => await Geolocator.checkPermission() == LocationPermission.always;

  /// Android 11+ sends the user to the app's settings page for "all the time";
  /// requestPermission alone cannot grant it. Returns whether it is granted now.
  Future<bool> requestBackground() async {
    await ensurePermission();
    if (await hasBackground()) return true;
    await Geolocator.requestPermission();
    if (await hasBackground()) return true;
    await Geolocator.openAppSettings();
    return hasBackground();
  }

  Future<void> openSettings() => Geolocator.openAppSettings();
}
