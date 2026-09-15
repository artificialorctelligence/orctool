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

  /// [newIndex] is the item's index after removal, as `ReorderableListView.onReorderItem` reports it.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final ids = ordered.map((i) => i.id).toList();
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
    if (on) {
      await scheduler.schedule(i.id, settingsFor(i).interval.duration);
      await prefs.setLogRun(i.id, '${i.id}-${DateTime.now().millisecondsSinceEpoch}');
    } else {
      await scheduler.cancel(i.id);
      await prefs.setLogRun(i.id, null);
    }
    await prefs.setLogging(i.id, on);
    notifyListeners();
  }

  /// Schedules before persisting (as [setLogging] does), so a scheduler
  /// failure leaves the previous settings in force rather than persisting
  /// a change the OS never actually picked up.
  Future<void> setLogSettings(Instrument i, LogSettings s) async {
    if (isLogging(i.id)) await scheduler.schedule(i.id, s.interval.duration);
    await prefs.setLogSettings(i.id, s);
    notifyListeners();
  }
}
