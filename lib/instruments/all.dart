import '../core/instrument.dart';
import '../core/prefs.dart';
import 'compass.dart';
import 'location.dart';
import 'location_service.dart';
import 'motion.dart';
import 'weather.dart';

/// Registration order is the default rail order. Adding an instrument in a
/// later slice is one file plus one line here.
List<Instrument> allInstruments(Prefs prefs) {
  final loc = LocationService(prefs: prefs);
  return [MotionInstrument(), CompassInstrument(), LocationInstrument(loc), WeatherInstrument(loc)];
}
