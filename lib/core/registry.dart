import 'package:flutter/foundation.dart';

import 'instrument.dart';
import 'prefs.dart';

/// Background scheduling, one periodic task per instrument id.
abstract class Scheduler {
  Future<void> schedule(String instrumentId, Duration every);
  Future<void> cancel(String instrumentId);
}

/// The instruments this phone has, in the user's order, with their prefs.
class Registry extends ChangeNotifier {
  Registry(this._all, this.prefs, this.scheduler);
  final List<Instrument> _all;
  final Prefs prefs;
  final Scheduler scheduler;
  List<Instrument> _available = const [];

  Future<void> probe() async {
    _available = [for (final i in _all) if (await i.isAvailable()) i];
    notifyListeners();
  }

  List<Instrument> get available => List.unmodifiable(_available);

  Instrument? byId(String id) => _available.where((i) => i.id == id).firstOrNull;

  /// User order; instruments not yet in the saved order come after, in registration order.
  List<Instrument> get ordered {
    final o = prefs.order;
    int key(Instrument i) {
      final p = o.indexOf(i.id);
      return p < 0 ? o.length + _available.indexOf(i) : p;
    }
    return [..._available]..sort((x, y) => key(x).compareTo(key(y)));
  }

  List<Instrument> get rail => [for (final i in ordered) if (isShown(i.id)) i];

  bool isShown(String id) => !prefs.hidden.contains(id);
  bool isLogging(String id) => prefs.logging.contains(id);
  LogSettings settingsFor(Instrument i) => prefs.logSettings(i.id) ?? i.defaultLogSettings;

  Future<void> reorder(int oldIndex, int newIndex) async {
    final ids = ordered.map((i) => i.id).toList();
    if (newIndex > oldIndex) newIndex--;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    await prefs.setOrder(ids);
    notifyListeners();
  }

  Future<void> setShown(String id, bool shown) async {
    await prefs.setHidden(id, !shown);
    notifyListeners();
  }

  Future<void> setLogging(Instrument i, bool on) async {
    if (!i.canLog) throw ArgumentError('${i.id} cannot log');
    await prefs.setLogging(i.id, on);
    if (on) {
      await prefs.setLogRun(i.id, '${i.id}-${DateTime.now().millisecondsSinceEpoch}');
      await scheduler.schedule(i.id, settingsFor(i).interval.duration);
    } else {
      await scheduler.cancel(i.id);
      await prefs.setLogRun(i.id, null);
    }
    notifyListeners();
  }

  Future<void> setLogSettings(Instrument i, LogSettings s) async {
    await prefs.setLogSettings(i.id, s);
    if (isLogging(i.id)) await scheduler.schedule(i.id, s.interval.duration);
    notifyListeners();
  }
}
