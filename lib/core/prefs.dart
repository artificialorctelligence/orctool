import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'instrument.dart';
import 'store.dart';

/// Everything the app remembers that is not a reading.
class Prefs extends ChangeNotifier {
  Prefs._(this._p);
  final SharedPreferencesWithCache _p;

  static Future<Prefs> open() async => Prefs._(await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions()));

  bool get railOut => _p.getBool('railOut') ?? true;
  String get skinId => _p.getString('skin') ?? 'plain';
  Limits get limits => Limits(retentionDays: _p.getInt('retentionDays') ?? 30, capBytes: _p.getInt('capBytes') ?? 50 * 1024 * 1024);
  List<String> get order => _p.getStringList('order') ?? const [];
  Set<String> get hidden => (_p.getStringList('hidden') ?? const []).toSet();
  Set<String> get logging => (_p.getStringList('logging') ?? const []).toSet();
  LogSettings? logSettings(String id) {
    final s = _p.getString('log.$id');
    return s == null ? null : LogSettings.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
  }
  String? logRun(String id) => _p.getString('logrun.$id');

  Future<void> setRailOut(bool v) => _set(() => _p.setBool('railOut', v));
  Future<void> setSkinId(String v) => _set(() => _p.setString('skin', v));
  Future<void> setLimits(Limits l) => _set(() async {
        await _p.setInt('retentionDays', l.retentionDays);
        await _p.setInt('capBytes', l.capBytes);
      });
  Future<void> setOrder(List<String> ids) => _set(() => _p.setStringList('order', ids));
  Future<void> setHidden(String id, bool hidden) => _toggle('hidden', id, hidden);
  Future<void> setLogging(String id, bool on) => _toggle('logging', id, on);
  Future<void> setLogSettings(String id, LogSettings s) => _set(() => _p.setString('log.$id', jsonEncode(s.toJson())));
  Future<void> setLogRun(String id, String? runId) => _set(() => runId == null ? _p.remove('logrun.$id') : _p.setString('logrun.$id', runId));

  Future<void> _toggle(String key, String id, bool on) => _set(() {
        final s = (_p.getStringList(key) ?? const []).toSet();
        on ? s.add(id) : s.remove(id);
        return _p.setStringList(key, s.toList()..sort());
      });

  Future<void> _set(Future<void> Function() write) async {
    await write();
    notifyListeners();
  }
}
