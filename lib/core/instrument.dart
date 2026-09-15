import 'package:flutter/material.dart';

enum LogInterval {
  m15(Duration(minutes: 15), '15 min'),
  hourly(Duration(hours: 1), 'hourly'),
  daily(Duration(days: 1), 'daily');

  const LogInterval(this.duration, this.label);
  final Duration duration;
  final String label;
}

/// Per-instrument logging settings. [interval] is common to every instrument;
/// [extra] is whatever the instrument's own details form edits.
class LogSettings {
  const LogSettings({this.interval = LogInterval.hourly, this.extra = const {}});

  final LogInterval interval;
  final Map<String, Object?> extra;

  Map<String, Object?> toJson() => {'interval': interval.name, 'extra': extra};

  factory LogSettings.fromJson(Map<String, Object?> j) => LogSettings(
        interval: LogInterval.values.asNameMap()[j['interval']] ?? LogInterval.hourly,
        extra: (j['extra'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  LogSettings copyWith({LogInterval? interval, Map<String, Object?>? extra}) =>
      LogSettings(interval: interval ?? this.interval, extra: extra ?? this.extra);
}

class Reading {
  const Reading(this.ts, this.values);
  final DateTime ts;
  final Map<String, num> values;
}

/// The one contract every instrument implements. The shell, recorder,
/// scheduler, store and settings know instruments only through this.
abstract class Instrument {
  String get id;
  String get name;

  /// Declared in code, per platform. False means no logging UI anywhere.
  bool get canLog;

  Duration get sampleTimeout => const Duration(seconds: 30);

  /// Probed once at launch; false means the instrument is not registered at all.
  Future<bool> isAvailable();

  Stream<Reading> live();

  /// One reading for the scheduler. May take seconds (a GPS fix).
  Future<Reading> sample();

  Widget buildLive(BuildContext context, Reading? reading);
  Widget buildDetail(BuildContext context, Reading? reading);

  /// Shown in the live band when [live] errors. Override to add actions.
  Widget buildError(BuildContext context, Object error, VoidCallback retry) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$error', textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ]);

  LogSettings get defaultLogSettings => const LogSettings();

  /// The settings in force for a scheduled sample. The scheduler sets this
  /// before calling [sample]; an instrument reads its own `extra` from it.
  LogSettings? _log;
  LogSettings get log => _log ?? defaultLogSettings;
  set log(LogSettings s) => _log = s;

  /// The instrument-specific part of the details form (below the interval picker).
  Widget buildLogSettings(BuildContext context, LogSettings current,
          ValueChanged<LogSettings> onChanged) =>
      const SizedBox.shrink();

  /// Null when logging may be turned on; otherwise the reason it can't be.
  Future<String?> logPrecondition() async => null;

  String logSummary(LogSettings s) => 'Log: ${s.interval.label}';

  /// Five decimals: 1 m of latitude, and far below any sensor's noise floor.
  Map<String, num> toRow(Reading r) => {
        for (final e in r.values.entries) e.key: e.value is int ? e.value : (e.value * 100000).round() / 100000,
      };
}
