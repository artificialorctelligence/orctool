# Orctool slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter app with a sliding-rail shell, two skins, four instruments (motion, compass, location, weather), session recording, scheduled background logging, and capped SQLite storage — built and run on direflail's Android phone.

**Architecture:** One abstract `Instrument` contract (`lib/core/instrument.dart`); the shell, recorder, scheduler, store, skins and settings are written once against it. Each instrument is one file. Readings from live sessions and from scheduled samples land in one SQLite table pruned by age and byte cap before every write.

**Tech Stack:** Flutter 3.47.4 / Dart 3.13.3 (stable 2026-09-11). Packages (live on pub.dev 2026-09-13): `sqflite` 2.4.4, `shared_preferences` 2.5.5, `sensors_plus` 7.1.0, `geolocator` 14.0.3, `http` 1.6.0, `workmanager` 0.10.10, `share_plus` 13.3.0, `path_provider` 2.1.6. Dev: `sqflite_common_ffi` 2.4.3, `shared_preferences_platform_interface` 2.4.2, `flutter_lints` (template default).

Spec: `docs/superpowers/specs/2026-09-13-orctool-slice-1-design.md`. Stack knowledge: `orclab:stack-flutter` (read it in full before Task 0). Test rules: `orclab:test-discipline`.

## Global Constraints

- Android is built and tested; iOS is configured (`--platforms android,ios`) but never built in this slice.
- `applicationId` / bundle id is `org.orctool.orctool` — fixed forever once uploaded to Play.
- No colour, radius or font literal outside `lib/skins/` (spec §3). Task 7 adds a test that greps for it.
- The console skin is never called "LCARS" anywhere — code, strings, assets, commits.
- No state-management or navigation package: `ChangeNotifier`, `ListenableBuilder`, `Navigator` only.
- Every `catch` block carries a comment (`empty_catches` is an error); no `assert` for runtime checks — throw `ArgumentError`.
- `flutter analyze --fatal-infos && flutter test` must pass before every commit.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- Before adding any plugin not listed above: check it ships `PrivacyInfo.xcprivacy`, and run the 16 KB check on the next release bundle (stack skill, "Choosing dependencies").

## File structure

```
pubspec.yaml                          deps, assets (fonts/Antonio)
analysis_options.yaml                 strict lints (stack skill "Lint")
android/app/src/main/AndroidManifest.xml   INTERNET, ACCESS_FINE_LOCATION, ACCESS_BACKGROUND_LOCATION
ios/Runner/Info.plist                 NSLocation*UsageDescription strings
assets/fonts/Antonio[wght].ttf, OFL.txt
lib/main.dart                         entry; workmanager callbackDispatcher; OrctoolApp
lib/core/instrument.dart              Instrument, Reading, LogSettings, LogInterval
lib/core/store.dart                   Store, Limits, RunSummary
lib/core/prefs.dart                   Prefs (ChangeNotifier over SharedPreferencesWithCache)
lib/core/registry.dart                Registry, Scheduler
lib/core/recorder.dart                Recorder, runScheduledSample
lib/core/csv.dart                     toCsv
lib/skins/skin.dart                   Skin, OrcTheme
lib/skins/plain.dart                  plainSkin
lib/skins/console.dart                consoleSkin
lib/skins/all.dart                    skins list, skinById
lib/shell/shell.dart                  Shell (title bar, rail, content)
lib/shell/instrument_screen.dart      three bands + RecordingBar
lib/shell/records_screen.dart         RecordsScreen, RunScreen
lib/shell/settings_screen.dart        SettingsScreen
lib/shell/instruments_screen.dart     InstrumentsScreen, LogSettingsScreen
lib/instruments/sensor_util.dart      firstEventWithin, merge2
lib/instruments/motion.dart           MotionInstrument
lib/instruments/compass.dart          CompassInstrument, headingDegrees
lib/instruments/location_service.dart LocationService
lib/instruments/location.dart         LocationInstrument
lib/instruments/weather.dart          WeatherInstrument, describeWmo
lib/instruments/all.dart              allInstruments()
lib/scheduler_workmanager.dart        WorkmanagerScheduler
test/fakes.dart                       FakeInstrument, memoryPrefs(), memoryStore()
test/... one file per unit (named in each task)
VERIFICATION.md                       on-phone checklist
```

---

### Task 0: Toolchain and scaffold

**Files:**
- Create: the Flutter project in `/home/direflail/projects/orctool` (existing git repo with `docs/`)
- Modify: `analysis_options.yaml`, `pubspec.yaml`, `.gitignore`

**Interfaces:**
- Produces: a project where `flutter analyze --fatal-infos && flutter test` passes; `flutter run` installs on the phone.

- [ ] **Step 1: Install prerequisites and the Flutter SDK**

Flutter is not installed on this machine (checked 2026-09-13: no `flutter`, no `java`, no `~/Android/Sdk`). JDK 17 is what the current Android Gradle Plugin needs.

```bash
sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa openjdk-17-jdk libsqlite3-dev
mkdir -p ~/development && cd ~/development
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.4-stable.tar.xz
tar -xf flutter_linux_3.47.4-stable.tar.xz
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.bashrc
echo 'export ANDROID_HOME="$HOME/Android/Sdk"' >> ~/.bashrc
echo 'export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"' >> ~/.bashrc
source ~/.bashrc && flutter --version
```

Expected: `Flutter 3.47.4 • channel stable`, `Dart 3.13.3`.

- [ ] **Step 2: Install the Android SDK with the command-line tools (no Android Studio)**

```bash
mkdir -p ~/Android/Sdk/cmdline-tools && cd ~/Android/Sdk/cmdline-tools
curl -LO https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
unzip -q commandlinetools-linux-15859902_latest.zip && mv cmdline-tools latest
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1" "emulator" "system-images;android-36;google_apis;x86_64"
flutter doctor --android-licenses
flutter doctor
avdmanager create avd --name orctool --package "system-images;android-36;google_apis;x86_64" --device pixel_7
```

Expected: `flutter doctor` shows `[✓] Flutter`, `[✓] Android toolchain`. `[!] Android Studio (not installed)` and `[!] Chrome` are fine. Anything else it lists as ✗ under Android toolchain: fix before continuing (its message says how). `avdmanager` answers "Do you wish to create a custom hardware profile" — answer `no` (pipe `echo no |` into it). If `sdkmanager` cannot find a package name above, list what exists with `sdkmanager --list | grep -E 'system-images;android-36|build-tools;36'` and use the closest current one; record the substitution in the report.

- [ ] **Step 3: Scaffold into the existing repo**

```bash
cd /home/direflail/projects/orctool
flutter create --org org.orctool --project-name orctool --platforms android,ios .
```

Expected: `All done!`; `lib/main.dart`, `android/`, `ios/`, `test/widget_test.dart`, `pubspec.yaml` exist; `docs/` untouched.

- [ ] **Step 4: Strict analysis options**

Replace `analysis_options.yaml` with:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    empty_catches: error
    unused_import: error
    unused_local_variable: error
    dead_code: error
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
```

- [ ] **Step 5: Dependencies**

```bash
flutter pub add sqflite:^2.4.4 shared_preferences:^2.5.5 sensors_plus:^7.1.0 geolocator:^14.0.3 http:^1.6.0 workmanager:^0.10.10 share_plus:^13.3.0 path_provider:^2.1.6
flutter pub add --dev sqflite_common_ffi:^2.4.3 shared_preferences_platform_interface:^2.4.2
```

- [ ] **Step 6: Remove the template test, add `.gitignore` entries, verify**

```bash
rm test/widget_test.dart
printf '.superpowers/\nandroid/key.properties\n' >> .gitignore
flutter analyze --fatal-infos && flutter test
```

Expected: analyze `No issues found!`; test `No tests ran` is acceptable here (exit 0 or 1 with "no tests" — either is fine at this step only).

- [ ] **Step 7: Run the template app on the emulator**

Start the emulator in the background, wait for it to boot, then run:

```bash
flutter emulators --launch orctool
adb wait-for-device && until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
flutter devices
flutter run -d emulator-5554 --no-resident   # exits after install+launch; the app stays running
```

Expected: `flutter devices` lists `sdk gphone64 x86_64 (mobile) • emulator-5554`; the counter demo is on the emulator screen (`adb exec-out screencap -p > /tmp/scaffold.png` to capture it). If the emulator fails to start with a KVM/hypervisor message, stop any running VirtualBox VM and retry; if `/dev/kvm` is not writable, report BLOCKED with the exact error — that needs the user in the `kvm` group. Development runs on this emulator; direflail's phone is used for `VERIFICATION.md` at the end of the slice.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Scaffold the Flutter project (Android + iOS), strict lints, dependencies

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 1: The Instrument contract and the test fakes

**Files:**
- Create: `lib/core/instrument.dart`, `test/fakes.dart`, `test/core/instrument_test.dart`

**Interfaces:**
- Produces:
  - `enum LogInterval { m15, hourly, daily }` with `Duration duration`, `String label`
  - `class LogSettings { LogInterval interval; Map<String, Object?> extra; toJson(); fromJson(); copyWith() }`
  - `class Reading { DateTime ts; Map<String, num> values; }`
  - `abstract class Instrument` — members exactly as in the code below
  - `FakeInstrument` in `test/fakes.dart`

- [ ] **Step 1: Write the failing test**

`test/core/instrument_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';

import '../fakes.dart';

void main() {
  test('LogSettings round-trips through JSON including extra', () {
    const s = LogSettings(interval: LogInterval.daily, extra: {'accuracy': 'high'});
    final back = LogSettings.fromJson(s.toJson());
    expect(back.interval, LogInterval.daily);
    expect(back.extra, {'accuracy': 'high'});
  });

  test('LogSettings.fromJson tolerates a missing interval', () {
    expect(LogSettings.fromJson(const {}).interval, LogInterval.hourly);
  });

  test('default toRow is the reading values and logSummary names the interval', () {
    final i = FakeInstrument();
    final r = Reading(DateTime(2026, 9, 13), const {'x': 1.5});
    expect(i.toRow(r), {'x': 1.5});
    expect(i.logSummary(const LogSettings(interval: LogInterval.m15)), 'Log: 15 min');
    expect(i.logPrecondition(), completion(isNull));
  });

  test('log falls back to defaultLogSettings until set', () {
    final i = FakeInstrument();
    expect(i.log.interval, LogInterval.hourly);
    i.log = const LogSettings(interval: LogInterval.daily);
    expect(i.log.interval, LogInterval.daily);
  });
}
```

`test/fakes.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:orctool/core/instrument.dart';

class FakeInstrument extends Instrument {
  FakeInstrument({
    this.id = 'fake',
    this.name = 'Fake',
    this.available = true,
    this.canLog = true,
    List<Reading>? script,
  }) : script = script ?? [Reading(DateTime(2026, 9, 13, 12), const {'v': 1})];

  @override
  final String id;
  @override
  final String name;
  final bool available;
  @override
  final bool canLog;
  final List<Reading> script;
  int sampleCalls = 0;

  @override
  Future<bool> isAvailable() async => available;
  @override
  Stream<Reading> live() => Stream.fromIterable(script);
  @override
  Future<Reading> sample() async {
    sampleCalls++;
    return script.first;
  }

  @override
  Widget buildLive(BuildContext context, Reading? reading) =>
      Text('live ${reading?.values['v']}');
  @override
  Widget buildDetail(BuildContext context, Reading? reading) =>
      Text('detail ${reading?.values['v']}');
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/instrument_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/core/instrument.dart'`.

- [ ] **Step 3: Write the contract**

`lib/core/instrument.dart`:

```dart
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

  Map<String, num> toRow(Reading r) => r.values;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/core/instrument_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/instrument.dart test/fakes.dart test/core/instrument_test.dart
git commit -m "Instrument contract, LogSettings, Reading, test fake

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Store — one readings table with retention

**Files:**
- Create: `lib/core/store.dart`, `test/core/store_test.dart`
- Modify: `test/fakes.dart` (add `memoryStore()`)

**Interfaces:**
- Produces:
  - `class Limits { int retentionDays = 30; int capBytes = 50 MiB }`
  - `class RunSummary { String runId, instrument, kind; int rows; DateTime first, last }`
  - `class Store` with `static Future<Store> open(String path)`, `Future<void> insert({instrument, runId, kind, ts, data, limits})`, `Future<int> totalBytes()`, `Future<List<RunSummary>> runs({String? kind})`, `Future<List<Map<String, Object?>>> rows(String runId)`, `Future<void> prune(Limits, {DateTime? now})`, `Future<void> close()`
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing test**

Add to `test/fakes.dart`:

```dart
import 'package:orctool/core/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Store> memoryStore() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return Store.open(inMemoryDatabasePath);
}
```

`test/core/store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/store.dart';

import '../fakes.dart';

void main() {
  late Store store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  final t0 = DateTime(2026, 9, 13, 12);
  Future<void> put(String run, DateTime ts, {String inst = 'compass', String kind = 'session', Limits limits = const Limits()}) =>
      store.insert(instrument: inst, runId: run, kind: kind, ts: ts, data: {'heading': 247.5, 'field': 48.2}, limits: limits);

  test('rows come back decoded, in time order, with ts', () async {
    await put('r1', t0.add(const Duration(seconds: 1)));
    await put('r1', t0);
    final rows = await store.rows('r1');
    expect(rows.map((r) => r['ts']), [t0, t0.add(const Duration(seconds: 1))]);
    expect(rows.first['heading'], 247.5);
  });

  test('runs summarises each run_id, newest first, filtered by kind', () async {
    await put('r1', t0);
    await put('r1', t0.add(const Duration(minutes: 1)));
    await put('log-w', t0.add(const Duration(hours: 1)), inst: 'weather', kind: 'log');
    final all = await store.runs();
    expect(all.map((r) => r.runId), ['log-w', 'r1']);
    expect(all.last.rows, 2);
    expect(all.last.first, t0);
    expect(all.last.last, t0.add(const Duration(minutes: 1)));
    expect((await store.runs(kind: 'log')).single.instrument, 'weather');
  });

  test('retention by age deletes rows older than retentionDays at write time', () async {
    await put('old', t0.subtract(const Duration(days: 31)));
    await put('new', t0, limits: const Limits(retentionDays: 30));
    expect((await store.runs()).map((r) => r.runId), ['new']);
  });

  test('retention by cap deletes the oldest rows until under capBytes', () async {
    const tiny = Limits(retentionDays: 365, capBytes: 120); // each row is ~31 bytes of data
    for (var i = 0; i < 10; i++) {
      await put('r', t0.add(Duration(seconds: i)), limits: tiny);
    }
    expect(await store.totalBytes(), lessThanOrEqualTo(120 + 31));
    final rows = await store.rows('r');
    expect(rows.last['ts'], t0.add(const Duration(seconds: 9)), reason: 'newest survives');
    expect(rows.length, lessThan(10));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/core/store.dart'`.

- [ ] **Step 3: Write the store**

`lib/core/store.dart`:

```dart
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class Limits {
  const Limits({this.retentionDays = 30, this.capBytes = 50 * 1024 * 1024});
  final int retentionDays;
  final int capBytes;
}

class RunSummary {
  const RunSummary({required this.runId, required this.instrument, required this.kind, required this.rows, required this.first, required this.last});
  final String runId;
  final String instrument;
  final String kind;
  final int rows;
  final DateTime first;
  final DateTime last;
}

/// One table for every instrument. `data` is the instrument's toRow() as JSON.
class Store {
  Store._(this._db);
  final Database _db;
  int _total = 0;
  DateTime? _lastAgePrune;

  static Future<Store> open(String path) async {
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE readings(id INTEGER PRIMARY KEY, instrument TEXT NOT NULL, run_id TEXT NOT NULL, kind TEXT NOT NULL, ts INTEGER NOT NULL, data TEXT NOT NULL)');
      await db.execute('CREATE INDEX idx_inst_ts ON readings(instrument, ts)');
      await db.execute('CREATE INDEX idx_run ON readings(run_id)');
      await db.execute('CREATE INDEX idx_ts ON readings(ts)');
    });
    final s = Store._(db);
    s._total = await s.totalBytes();
    return s;
  }

  Future<void> close() => _db.close();

  Future<void> insert({required String instrument, required String runId, required String kind, required DateTime ts, required Map<String, num> data, required Limits limits}) async {
    final json = jsonEncode(data);
    await prune(limits, now: ts, incoming: json.length);
    await _db.insert('readings', {'instrument': instrument, 'run_id': runId, 'kind': kind, 'ts': ts.millisecondsSinceEpoch, 'data': json});
    _total += json.length;
  }

  /// Age prune at most once a minute (it rescans the total); cap prune on every
  /// write from the cached total, so the cap is never exceeded by more than one row.
  Future<void> prune(Limits limits, {DateTime? now, int incoming = 0}) async {
    final t = now ?? DateTime.now();
    if (_lastAgePrune == null || t.difference(_lastAgePrune!).abs() > const Duration(minutes: 1)) {
      final cutoff = t.subtract(Duration(days: limits.retentionDays)).millisecondsSinceEpoch;
      await _db.delete('readings', where: 'ts < ?', whereArgs: [cutoff]);
      _total = await totalBytes();
      _lastAgePrune = t;
    }
    while (_total + incoming > limits.capBytes && _total > 0) {
      // ponytail: 100 rows per pass, then rescan; fine at a 50 MB cap.
      await _db.rawDelete('DELETE FROM readings WHERE id IN (SELECT id FROM readings ORDER BY ts ASC LIMIT 100)');
      _total = await totalBytes();
    }
  }

  Future<int> totalBytes() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COALESCE(SUM(LENGTH(data)), 0) FROM readings')) ?? 0;

  Future<List<RunSummary>> runs({String? kind}) async {
    final r = await _db.rawQuery(
      'SELECT run_id, instrument, kind, COUNT(*) n, MIN(ts) t0, MAX(ts) t1 FROM readings'
      '${kind == null ? '' : ' WHERE kind = ?'} GROUP BY run_id ORDER BY t1 DESC',
      kind == null ? null : [kind],
    );
    return [
      for (final m in r)
        RunSummary(
          runId: m['run_id'] as String,
          instrument: m['instrument'] as String,
          kind: m['kind'] as String,
          rows: m['n'] as int,
          first: DateTime.fromMillisecondsSinceEpoch(m['t0'] as int),
          last: DateTime.fromMillisecondsSinceEpoch(m['t1'] as int),
        ),
    ];
  }

  /// Each row is {'ts': DateTime, ...decoded data}.
  Future<List<Map<String, Object?>>> rows(String runId) async {
    final r = await _db.query('readings', columns: ['ts', 'data'], where: 'run_id = ?', whereArgs: [runId], orderBy: 'ts ASC');
    return [
      for (final m in r)
        {
          'ts': DateTime.fromMillisecondsSinceEpoch(m['ts'] as int),
          ...(jsonDecode(m['data'] as String) as Map).cast<String, Object?>(),
        },
    ];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/core/store_test.dart`
Expected: PASS (4 tests). If the cap test's byte arithmetic is off by a few bytes, adjust the `tiny` cap in the test to the real encoded row length printed by `jsonEncode({'heading': 247.5, 'field': 48.2}).length` (31) — do not loosen the "newest survives" assertion.

- [ ] **Step 5: Commit**

```bash
git add lib/core/store.dart test/core/store_test.dart test/fakes.dart
git commit -m "Store: one readings table, retention by age and by byte cap

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Prefs

**Files:**
- Create: `lib/core/prefs.dart`, `test/core/prefs_test.dart`
- Modify: `test/fakes.dart` (add `memoryPrefs()`)

**Interfaces:**
- Produces `class Prefs extends ChangeNotifier`:
  - `static Future<Prefs> open()`
  - getters: `bool railOut`, `String skinId`, `Limits limits`, `List<String> order`, `Set<String> hidden`, `Set<String> logging`, `LogSettings? logSettings(String id)`, `String? logRun(String id)`
  - setters (all `Future<void>`, all `notifyListeners()`): `setRailOut(bool)`, `setSkinId(String)`, `setLimits(Limits)`, `setOrder(List<String>)`, `setHidden(String id, bool)`, `setLogging(String id, bool)`, `setLogSettings(String id, LogSettings)`, `setLogRun(String id, String? runId)`
- Consumes: `Limits` (Task 2), `LogSettings` (Task 1).

- [ ] **Step 1: Write the failing test**

Add to `test/fakes.dart`:

```dart
import 'package:orctool/core/prefs.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<Prefs> memoryPrefs() {
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  return Prefs.open();
}
```

`test/core/prefs_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/prefs.dart';
import 'package:orctool/core/store.dart';

import '../fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Prefs p;
  setUp(() async => p = await memoryPrefs());

  test('defaults', () {
    expect(p.railOut, isTrue);
    expect(p.skinId, 'plain');
    expect(p.limits.retentionDays, 30);
    expect(p.limits.capBytes, 50 * 1024 * 1024);
    expect(p.order, isEmpty);
    expect(p.hidden, isEmpty);
    expect(p.logging, isEmpty);
    expect(p.logSettings('x'), isNull);
    expect(p.logRun('x'), isNull);
  });

  test('every setter persists, and notifies', () async {
    var notified = 0;
    p.addListener(() => notified++);
    await p.setRailOut(false);
    await p.setSkinId('console');
    await p.setLimits(const Limits(retentionDays: 7, capBytes: 10));
    await p.setOrder(['b', 'a']);
    await p.setHidden('a', true);
    await p.setLogging('b', true);
    await p.setLogSettings('b', const LogSettings(interval: LogInterval.daily, extra: {'k': 1}));
    await p.setLogRun('b', 'run-1');
    final q = await Prefs.open(); // same in-memory platform instance
    expect(q.railOut, isFalse);
    expect(q.skinId, 'console');
    expect(q.limits.retentionDays, 7);
    expect(q.limits.capBytes, 10);
    expect(q.order, ['b', 'a']);
    expect(q.hidden, {'a'});
    expect(q.logging, {'b'});
    expect(q.logSettings('b')!.interval, LogInterval.daily);
    expect(q.logSettings('b')!.extra, {'k': 1});
    expect(q.logRun('b'), 'run-1');
    expect(notified, 8);
    await p.setHidden('a', false);
    await p.setLogging('b', false);
    await p.setLogRun('b', null);
    expect(p.hidden, isEmpty);
    expect(p.logging, isEmpty);
    expect(p.logRun('b'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/prefs_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/core/prefs.dart'`.

- [ ] **Step 3: Write Prefs**

`lib/core/prefs.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/core/prefs_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/prefs.dart test/core/prefs_test.dart test/fakes.dart
git commit -m "Prefs: rail state, skin, limits, registry preferences

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 4: Registry and the Scheduler interface

**Files:**
- Create: `lib/core/registry.dart`, `test/core/registry_test.dart`

**Interfaces:**
- Produces:
  - `abstract class Scheduler { Future<void> schedule(String instrumentId, Duration every); Future<void> cancel(String instrumentId); }`
  - `class Registry extends ChangeNotifier`: `Registry(List<Instrument> all, Prefs prefs, Scheduler scheduler)`, `Future<void> probe()`, `List<Instrument> available`, `List<Instrument> ordered`, `List<Instrument> rail`, `Instrument? byId(String)`, `bool isShown(String)`, `bool isLogging(String)`, `LogSettings settingsFor(Instrument)`, `Future<void> reorder(int oldIndex, int newIndex)`, `Future<void> setShown(String id, bool)`, `Future<void> setLogging(Instrument, bool)`, `Future<void> setLogSettings(Instrument, LogSettings)`
- Consumes: `Instrument`, `LogSettings` (Task 1); `Prefs` (Task 3).

- [ ] **Step 1: Write the failing test**

`test/core/registry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/registry.dart';

import '../fakes.dart';

class SpyScheduler implements Scheduler {
  final calls = <String>[];
  @override
  Future<void> schedule(String id, Duration every) async => calls.add('schedule $id ${every.inMinutes}');
  @override
  Future<void> cancel(String id) async => calls.add('cancel $id');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SpyScheduler sched;
  late FakeInstrument a, b, gone, noLog;
  late Registry reg;

  setUp(() async {
    sched = SpyScheduler();
    a = FakeInstrument(id: 'a');
    b = FakeInstrument(id: 'b');
    gone = FakeInstrument(id: 'gone', available: false);
    noLog = FakeInstrument(id: 'nolog', canLog: false);
    reg = Registry([a, gone, b, noLog], await memoryPrefs(), sched);
    await reg.probe();
  });

  test('probe drops unavailable instruments and keeps registration order', () {
    expect(reg.available.map((i) => i.id), ['a', 'b', 'nolog']);
    expect(reg.byId('gone'), isNull);
  });

  test('reorder persists and rail follows it; hidden leaves the rail but not the list', () async {
    await reg.reorder(0, 3); // a to the end
    expect(reg.ordered.map((i) => i.id), ['b', 'nolog', 'a']);
    await reg.setShown('nolog', false);
    expect(reg.rail.map((i) => i.id), ['b', 'a']);
    expect(reg.ordered.map((i) => i.id), ['b', 'nolog', 'a']);
    expect(reg.isShown('nolog'), isFalse);
  });

  test('logging on schedules with the interval, starts a run, and off cancels', () async {
    await reg.setLogSettings(a, const LogSettings(interval: LogInterval.daily));
    await reg.setLogging(a, true);
    expect(reg.isLogging('a'), isTrue);
    expect(reg.prefs.logRun('a'), isNotNull);
    expect(sched.calls, ['schedule a 1440']);
    await reg.setLogSettings(a, const LogSettings(interval: LogInterval.m15));
    expect(sched.calls.last, 'schedule a 15');
    await reg.setLogging(a, false);
    expect(sched.calls.last, 'cancel a');
    expect(reg.prefs.logRun('a'), isNull);
  });

  test('settingsFor falls back to the instrument default', () {
    expect(reg.settingsFor(b).interval, LogInterval.hourly);
  });

  test('logging an instrument that cannot log is an error', () {
    expect(() => reg.setLogging(noLog, true), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/registry_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/core/registry.dart'`.

- [ ] **Step 3: Write the registry**

`lib/core/registry.dart`:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/core/registry_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/registry.dart test/core/registry_test.dart
git commit -m "Registry: availability probe, user order, show/log prefs, scheduler hooks

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Recorder — sessions and the scheduled sample

**Files:**
- Create: `lib/core/recorder.dart`, `test/core/recorder_test.dart`

**Interfaces:**
- Produces:
  - `class Recorder extends ChangeNotifier`: `Recorder(Store store, Prefs prefs)`, `bool recording`, `Instrument? instrument`, `DateTime? startedAt`, `String? error`, `void start(Instrument)`, `Future<void> stop()`
  - `Future<void> runScheduledSample(Instrument i, Store store, Prefs prefs)`
- Consumes: `Store` (Task 2), `Prefs` (Task 3), `Instrument` (Task 1).

- [ ] **Step 1: Write the failing test**

`test/core/recorder_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/recorder.dart';

import '../fakes.dart';

class ErrorInstrument extends FakeInstrument {
  ErrorInstrument() : super(id: 'err');
  @override
  Stream<Reading> live() async* {
    yield script.first;
    throw StateError('sensor gone');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final t0 = DateTime(2026, 9, 13, 12);

  test('a session writes exactly the streamed readings under one run_id', () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    final i = FakeInstrument(id: 'compass', script: [
      Reading(t0, const {'heading': 1}),
      Reading(t0.add(const Duration(seconds: 1)), const {'heading': 2}),
    ]);
    rec.start(i);
    expect(rec.recording, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let the stream drain and the inserts land
    await rec.stop();
    expect(rec.recording, isFalse);
    final runs = await store.runs();
    expect(runs.single.instrument, 'compass');
    expect(runs.single.kind, 'session');
    expect(runs.single.rows, 2);
    expect((await store.rows(runs.single.runId)).map((r) => r['heading']), [1, 2]);
  });

  test('a stream error keeps the rows so far and stops cleanly', () async {
    final store = await memoryStore();
    final rec = Recorder(store, await memoryPrefs());
    rec.start(ErrorInstrument());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rec.recording, isFalse);
    expect(rec.error, contains('sensor gone'));
    expect((await store.runs()).single.rows, 1);
  });

  test('a scheduled sample writes one log row under the log run, silently skips failures', () async {
    final store = await memoryStore();
    final prefs = await memoryPrefs();
    await prefs.setLogRun('weather', 'weather-run');
    await prefs.setLogSettings('weather', const LogSettings(interval: LogInterval.daily));
    final i = FakeInstrument(id: 'weather', script: [Reading(t0, const {'temp': 19.3})]);
    await runScheduledSample(i, store, prefs);
    await runScheduledSample(i, store, prefs);
    expect(i.log.interval, LogInterval.daily, reason: 'settings handed over before sampling');
    final run = (await store.runs()).single;
    expect(run.runId, 'weather-run');
    expect(run.kind, 'log');
    expect(run.rows, 2);
    await runScheduledSample(ErrorInstrumentSample(), store, prefs);
    expect((await store.runs()).single.rows, 2, reason: 'failure wrote nothing');
  });
}

class ErrorInstrumentSample extends FakeInstrument {
  ErrorInstrumentSample() : super(id: 'weather');
  @override
  Future<Reading> sample() => Future.error(TimeoutException('no fix'));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/recorder_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/core/recorder.dart'`.

- [ ] **Step 3: Write the recorder**

`lib/core/recorder.dart`:

```dart
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'instrument.dart';
import 'prefs.dart';
import 'store.dart';

/// One session at a time: an extra sink on the instrument's live stream.
class Recorder extends ChangeNotifier {
  Recorder(this.store, this.prefs);
  final Store store;
  final Prefs prefs;

  StreamSubscription<Reading>? _sub;
  Instrument? instrument;
  DateTime? startedAt;
  String? _runId;
  String? error;

  bool get recording => _sub != null;

  void start(Instrument i) {
    if (recording) return;
    instrument = i;
    startedAt = DateTime.now();
    error = null;
    _runId = '${i.id}-${startedAt!.millisecondsSinceEpoch}';
    _sub = i.live().listen(
      (r) => store
          .insert(instrument: i.id, runId: _runId!, kind: 'session', ts: r.ts, data: i.toRow(r), limits: prefs.limits)
          .catchError((Object e) => _fail('Could not save: $e')),
      onError: (Object e) => _fail('$e'),
      onDone: stop,
    );
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    stop();
  }
}

/// The scheduler's callback: one sample, one row. Failures are silent — the
/// next scheduled run is the retry (spec §5).
Future<void> runScheduledSample(Instrument i, Store store, Prefs prefs) async {
  try {
    i.log = prefs.logSettings(i.id) ?? i.defaultLogSettings;
    final r = await i.sample().timeout(i.sampleTimeout);
    await store.insert(instrument: i.id, runId: prefs.logRun(i.id) ?? i.id, kind: 'log', ts: r.ts, data: i.toRow(r), limits: prefs.limits);
  } catch (e) {
    // Spec §5: no row, no retry; the gap shows in Records.
    debugPrint('scheduled sample ${i.id} failed: $e');
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/core/recorder_test.dart`
Expected: PASS (3 tests). If a test sees fewer rows than expected, the inserts hadn't landed yet — lengthen the delay in the test, not anything in the recorder.

- [ ] **Step 5: Commit**

```bash
git add lib/core/recorder.dart test/core/recorder_test.dart
git commit -m "Recorder: sessions as a sink on live(), scheduled sample as one row

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 6: Skins — OrcTheme, plain, console

**Files:**
- Create: `lib/skins/skin.dart`, `lib/skins/plain.dart`, `lib/skins/console.dart`, `lib/skins/all.dart`, `assets/fonts/Antonio[wght].ttf`, `assets/fonts/OFL.txt`, `test/skins/skins_test.dart`
- Modify: `pubspec.yaml` (fonts)

**Interfaces:**
- Produces:
  - `class OrcTheme extends ThemeExtension<OrcTheme>` with `Color accent, onAccent, panel, ground`, `double railRadius`, `bool railStripe, uppercase`, `String? displayFont`, `static OrcTheme of(BuildContext)`, `String text(String)` (uppercases when `uppercase`)
  - `class Skin { String id, name; ThemeData light, dark; }`
  - `final List<Skin> skins`, `Skin skinById(String id)` (falls back to plain)

- [ ] **Step 1: Fetch the typeface**

```bash
mkdir -p assets/fonts && cd assets/fonts
curl -sLo 'Antonio[wght].ttf' 'https://raw.githubusercontent.com/google/fonts/main/ofl/antonio/Antonio%5Bwght%5D.ttf'
curl -sLo OFL.txt https://raw.githubusercontent.com/google/fonts/main/ofl/antonio/OFL.txt
file 'Antonio[wght].ttf' && cd -
```

Expected: `TrueType Font data`. Add to `pubspec.yaml` under `flutter:`:

```yaml
  fonts:
    - family: Antonio
      fonts:
        - asset: assets/fonts/Antonio[wght].ttf
```

- [ ] **Step 2: Write the failing test**

`test/skins/skins_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/skins/all.dart';
import 'package:orctool/skins/skin.dart';

void main() {
  test('two skins; unknown id falls back to plain', () {
    expect(skins.map((s) => s.id), ['plain', 'console']);
    expect(skinById('nope').id, 'plain');
  });

  test('every ThemeData carries an OrcTheme', () {
    for (final s in skins) {
      expect(s.light.extension<OrcTheme>(), isNotNull, reason: s.id);
      expect(s.dark.extension<OrcTheme>(), isNotNull, reason: s.id);
    }
  });

  test('console is uppercase Antonio; plain is neither', () {
    final c = skinById('console').dark.extension<OrcTheme>()!;
    expect(c.uppercase, isTrue);
    expect(c.displayFont, 'Antonio');
    expect(c.text('Compass'), 'COMPASS');
    final p = skinById('plain').light.extension<OrcTheme>()!;
    expect(p.uppercase, isFalse);
    expect(p.text('Compass'), 'Compass');
  });

  test('no colour or radius literals outside lib/skins', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (f.path.startsWith('lib/skins/') || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r'Color\(0x|Colors\.[a-z]').hasMatch(src)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/skins/skins_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/skins/all.dart'`.

- [ ] **Step 4: Write the skins**

`lib/skins/skin.dart`:

```dart
import 'package:flutter/material.dart';

/// What Material's theme does not carry: the rail and title-bar language.
class OrcTheme extends ThemeExtension<OrcTheme> {
  const OrcTheme({
    required this.accent,
    required this.onAccent,
    required this.panel,
    required this.ground,
    required this.railRadius,
    required this.railStripe,
    required this.uppercase,
    this.displayFont,
  });

  final Color accent;
  final Color onAccent;
  final Color panel;
  final Color ground;
  final double railRadius;
  final bool railStripe;
  final bool uppercase;
  final String? displayFont;

  static OrcTheme of(BuildContext context) => Theme.of(context).extension<OrcTheme>()!;

  String text(String s) => uppercase ? s.toUpperCase() : s;

  @override
  OrcTheme copyWith({Color? accent, Color? onAccent, Color? panel, Color? ground, double? railRadius, bool? railStripe, bool? uppercase, String? displayFont}) => OrcTheme(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        panel: panel ?? this.panel,
        ground: ground ?? this.ground,
        railRadius: railRadius ?? this.railRadius,
        railStripe: railStripe ?? this.railStripe,
        uppercase: uppercase ?? this.uppercase,
        displayFont: displayFont ?? this.displayFont,
      );

  @override
  OrcTheme lerp(OrcTheme? other, double t) {
    if (other == null) return this;
    return OrcTheme(
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      ground: Color.lerp(ground, other.ground, t)!,
      railRadius: railRadius + (other.railRadius - railRadius) * t,
      railStripe: t < 0.5 ? railStripe : other.railStripe,
      uppercase: t < 0.5 ? uppercase : other.uppercase,
      displayFont: t < 0.5 ? displayFont : other.displayFont,
    );
  }
}

class Skin {
  const Skin({required this.id, required this.name, required this.light, required this.dark});
  final String id;
  final String name;
  final ThemeData light;
  final ThemeData dark;
}
```

`lib/skins/plain.dart`:

```dart
import 'package:flutter/material.dart';

import 'skin.dart';

ThemeData _plain(Brightness b) {
  final base = ThemeData(colorSchemeSeed: Colors.blue, brightness: b);
  final cs = base.colorScheme;
  return base.copyWith(extensions: [
    OrcTheme(
      accent: cs.primary,
      onAccent: cs.onPrimary,
      panel: cs.surfaceContainerHighest,
      ground: cs.surface,
      railRadius: 6,
      railStripe: false,
      uppercase: false,
    ),
  ]);
}

/// Material 3, follows the system light/dark. The default.
final plainSkin = Skin(id: 'plain', name: 'Plain', light: _plain(Brightness.light), dark: _plain(Brightness.dark));
```

`lib/skins/console.dart`:

```dart
import 'package:flutter/material.dart';

import 'skin.dart';

const _ground = Color(0xFF0B0B10);
const _panel = Color(0xFF1E2230);
const _accent = Color(0xFFF2B56B);

final ThemeData _console = ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(seedColor: _accent, brightness: Brightness.dark, surface: _ground, primary: _accent, onPrimary: _ground),
  scaffoldBackgroundColor: _ground,
  fontFamily: 'Antonio',
  extensions: const [
    OrcTheme(
      accent: _accent,
      onAccent: _ground,
      panel: _panel,
      ground: _ground,
      railRadius: 8,
      railStripe: true,
      uppercase: true,
      displayFont: 'Antonio',
    ),
  ],
);

/// Ship's-console look: near-black, one warm accent, condensed uppercase type.
/// Adjacent to a certain famous interface; deliberately not it.
final consoleSkin = Skin(id: 'console', name: 'Console', light: _console, dark: _console);
```

`lib/skins/all.dart`:

```dart
import 'console.dart';
import 'plain.dart';
import 'skin.dart';

final List<Skin> skins = [plainSkin, consoleSkin];

Skin skinById(String id) => skins.firstWhere((s) => s.id == id, orElse: () => plainSkin);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter pub get && flutter analyze --fatal-infos && flutter test test/skins/skins_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/skins assets/fonts pubspec.yaml test/skins/skins_test.dart
git commit -m "Skins: OrcTheme extension, plain and console skins, Antonio (OFL)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: The shell — title bar, sliding rail, content

**Files:**
- Create: `lib/shell/shell.dart`, `test/shell/shell_test.dart`

**Interfaces:**
- Produces: `class Shell extends StatefulWidget { Shell({registry, recorder, prefs, store, Widget Function(BuildContext, Instrument) instrumentBuilder, Widget Function(BuildContext) recordsBuilder, Widget Function(BuildContext) settingsBuilder}) }` — the three builders decouple this task from Tasks 8, 13, 14; `main.dart` (Task 15) wires the real screens in.
- Consumes: `Registry` (4), `Recorder` (5), `Prefs` (3), `Store` (2), `OrcTheme` (6).

- [ ] **Step 1: Write the failing test**

`test/shell/shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/prefs.dart';
import 'package:orctool/core/recorder.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/shell.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

void main() {
  late Prefs prefs;
  late Registry reg;

  Future<void> pump(WidgetTester t, {String skin = 'plain'}) async {
    await t.pumpWidget(MaterialApp(
      theme: skinById(skin).light,
      home: Shell(
        registry: reg,
        recorder: Recorder(await memoryStore(), prefs),
        prefs: prefs,
        store: await memoryStore(),
        instrumentBuilder: (_, i) => Text('screen:${i.id}'),
        recordsBuilder: (_) => const Text('screen:records'),
        settingsBuilder: (_) => const Text('screen:settings'),
      ),
    ));
    await t.pumpAndSettle();
  }

  setUp(() async {
    prefs = await memoryPrefs();
    reg = Registry([FakeInstrument(id: 'motion', name: 'Motion'), FakeInstrument(id: 'compass', name: 'Compass')], prefs, SpyScheduler());
    await reg.probe();
  });

  testWidgets('rail lists instruments then Records then Settings; first instrument is selected', (t) async {
    await pump(t);
    expect(find.text('Motion'), findsOneWidget);
    expect(find.text('Compass'), findsOneWidget);
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('screen:motion'), findsOneWidget);
  });

  testWidgets('tapping a rail entry switches content and does not move the rail', (t) async {
    await pump(t);
    await t.tap(find.text('Records'));
    await t.pumpAndSettle();
    expect(find.text('screen:records'), findsOneWidget);
    expect(prefs.railOut, isTrue);
    expect(find.text('Compass'), findsOneWidget);
  });

  testWidgets('tapping the title bar slides the rail in, names the instrument, persists', (t) async {
    await pump(t);
    await t.tap(find.text('Compass'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('title-instrument')), findsNothing);
    await t.tap(find.byKey(const Key('title-bar')));
    await t.pumpAndSettle();
    expect(prefs.railOut, isFalse);
    expect(find.text('Motion'), findsNothing);
    expect(find.descendant(of: find.byKey(const Key('title-instrument')), matching: find.text('Compass')), findsOneWidget);
    await t.tap(find.byKey(const Key('title-bar')));
    await t.pumpAndSettle();
    expect(prefs.railOut, isTrue);
  });

  testWidgets('console skin uppercases the rail', (t) async {
    await pump(t, skin: 'console');
    expect(find.text('COMPASS'), findsOneWidget);
  });

  testWidgets('hiding the selected instrument falls back to the first rail entry', (t) async {
    await pump(t);
    await reg.setShown('motion', false);
    await t.pumpAndSettle();
    expect(find.text('Motion'), findsNothing);
    expect(find.text('screen:compass'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/shell_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/shell/shell.dart'`.

- [ ] **Step 3: Write the shell**

`lib/shell/shell.dart`:

```dart
import 'package:flutter/material.dart';

import '../core/instrument.dart';
import '../core/prefs.dart';
import '../core/recorder.dart';
import '../core/registry.dart';
import '../core/store.dart';
import '../skins/skin.dart';

const _railWidth = 120.0;
const _records = 'records';
const _settings = 'settings';

/// Title bar (tap toggles the rail), sliding rail, content. The rail is the
/// navigation; nothing else moves it.
class Shell extends StatefulWidget {
  const Shell({
    super.key,
    required this.registry,
    required this.recorder,
    required this.prefs,
    required this.store,
    required this.instrumentBuilder,
    required this.recordsBuilder,
    required this.settingsBuilder,
  });

  final Registry registry;
  final Recorder recorder;
  final Prefs prefs;
  final Store store;
  final Widget Function(BuildContext, Instrument) instrumentBuilder;
  final WidgetBuilder recordsBuilder;
  final WidgetBuilder settingsBuilder;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  String? _selected;

  String get _current {
    final s = _selected;
    if (s == _records || s == _settings) return s!;
    if (s != null && widget.registry.rail.any((i) => i.id == s)) return s;
    return widget.registry.rail.firstOrNull?.id ?? _records;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.registry, widget.prefs]),
      builder: (context, _) {
        final orc = OrcTheme.of(context);
        final railOut = widget.prefs.railOut;
        final current = _current;
        final instrument = widget.registry.byId(current);
        return Scaffold(
          backgroundColor: orc.ground,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                _TitleBar(
                  instrumentName: railOut ? null : (instrument?.name ?? _fixedName(current)),
                  onTap: () => widget.prefs.setRailOut(!railOut),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: railOut ? _railWidth : 0,
                      // Content leaves the tree when slid in (it must not stay findable/tappable).
                      child: !railOut ? null : ClipRect(
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: _railWidth,
                          maxWidth: _railWidth,
                          child: _Rail(
                            entries: [
                              for (final i in widget.registry.rail) (i.id, i.name),
                              (_records, 'Records'),
                              (_settings, 'Settings'),
                            ],
                            selected: current,
                            onSelect: (id) => setState(() => _selected = id),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: railOut ? 8 : 0),
                    Expanded(
                      child: switch (current) {
                        _records => widget.recordsBuilder(context),
                        _settings => widget.settingsBuilder(context),
                        _ => widget.instrumentBuilder(context, instrument!),
                      },
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  String _fixedName(String id) => id == _records ? 'Records' : 'Settings';
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.instrumentName, required this.onTap});
  final String? instrumentName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final style = Theme.of(context).textTheme.titleMedium!.copyWith(color: orc.onAccent, fontFamily: orc.displayFont);
    return GestureDetector(
      key: const Key('title-bar'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: orc.accent, borderRadius: BorderRadius.circular(orc.railRadius)),
        child: Row(children: [
          Text(orc.text('Orctool'), style: style.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: instrumentName == null ? 0 : 1,
            child: Text(orc.text(instrumentName ?? ''), key: instrumentName == null ? null : const Key('title-instrument'), style: style),
          ),
        ]),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.entries, required this.selected, required this.onSelect});
  final List<(String, String)> entries;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return ListView(
      children: [
        for (final (id, name) in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(orc.railRadius),
              onTap: () => onSelect(id),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: id == selected ? orc.accent : orc.panel,
                  borderRadius: BorderRadius.circular(orc.railRadius),
                  border: orc.railStripe ? Border(left: BorderSide(color: orc.accent, width: 4)) : null,
                ),
                child: Text(
                  orc.text(name),
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall!.copyWith(
                        color: id == selected ? orc.onAccent : orc.accent,
                        fontFamily: orc.displayFont,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/shell/shell_test.dart test/skins/skins_test.dart`
Expected: PASS. The skins test's literal scan must still pass — `shell.dart` has no `Color(0x` or `Colors.`.

- [ ] **Step 5: Commit**

```bash
git add lib/shell/shell.dart test/shell/shell_test.dart
git commit -m "Shell: tap-to-slide rail, title bar names the instrument when the rail is in

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 8: Instrument screen — three bands and the recording bar

**Files:**
- Create: `lib/shell/instrument_screen.dart`, `test/shell/instrument_screen_test.dart`

**Interfaces:**
- Produces: `class InstrumentScreen extends StatefulWidget { InstrumentScreen({instrument, registry, recorder}) }`
- Consumes: `Instrument` (1), `Registry` (4), `Recorder` (5), `OrcTheme` (6).

- [ ] **Step 1: Write the failing test**

`test/shell/instrument_screen_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/recorder.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/instrument_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

class Controlled extends FakeInstrument {
  Controlled({super.canLog}) : super(id: 'c', name: 'Controlled');
  final ctl = StreamController<Reading>.broadcast();
  @override
  Stream<Reading> live() => ctl.stream;
}

void main() {
  late Registry reg;
  late Recorder rec;

  Future<void> pump(WidgetTester t, Instrument i) async {
    reg = Registry([i], await memoryPrefs(), SpyScheduler());
    await reg.probe();
    rec = Recorder(await memoryStore(), reg.prefs);
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: InstrumentScreen(instrument: i, registry: reg, recorder: rec))));
    await t.pump();
  }

  testWidgets('live and detail bands render each reading', (t) async {
    final i = Controlled();
    await pump(t, i);
    i.ctl.add(Reading(DateTime(2026), const {'v': 7}));
    await t.pump();
    expect(find.text('live 7'), findsOneWidget);
    expect(find.text('detail 7'), findsOneWidget);
    await t.pumpWidget(const SizedBox()); // dispose the recording bar's timer
  });

  testWidgets('record button starts and stops a session; timer shows', (t) async {
    final i = Controlled();
    await pump(t, i);
    await t.tap(find.byKey(const Key('record')));
    await t.pump();
    expect(rec.recording, isTrue);
    expect(rec.instrument, same(i));
    await t.pump(const Duration(seconds: 2));
    expect(find.textContaining('00:0'), findsOneWidget);
    await t.tap(find.byKey(const Key('record')));
    await t.pump();
    expect(rec.recording, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('log chip only when logging is on; absent when canLog is false', (t) async {
    final i = Controlled();
    await pump(t, i);
    expect(find.textContaining('Log:'), findsNothing);
    await reg.setLogging(i, true);
    await t.pump();
    expect(find.text('Log: hourly'), findsOneWidget);
    final noLog = Controlled(canLog: false);
    await pump(t, noLog);
    expect(find.textContaining('Log:'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a stream error shows the error band with Retry and disables recording', (t) async {
    final i = Controlled();
    await pump(t, i);
    i.ctl.addError(StateError('no data'));
    await t.pump();
    expect(find.textContaining('no data'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await t.tap(find.byKey(const Key('record')));
    await t.pump();
    expect(rec.recording, isFalse);
    await t.tap(find.text('Retry'));
    await t.pump();
    i.ctl.add(Reading(DateTime(2026), const {'v': 8}));
    await t.pump();
    expect(find.text('live 8'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/instrument_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:orctool/shell/instrument_screen.dart'`.

- [ ] **Step 3: Write the screen**

`lib/shell/instrument_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/instrument.dart';
import '../core/recorder.dart';
import '../core/registry.dart';
import '../skins/skin.dart';

/// Live band, detail band, recording bar — the same for every instrument.
class InstrumentScreen extends StatefulWidget {
  const InstrumentScreen({super.key, required this.instrument, required this.registry, required this.recorder});
  final Instrument instrument;
  final Registry registry;
  final Recorder recorder;

  @override
  State<InstrumentScreen> createState() => _InstrumentScreenState();
}

class _InstrumentScreenState extends State<InstrumentScreen> {
  late Stream<Reading> _stream = widget.instrument.live();

  void _retry() => setState(() => _stream = widget.instrument.live());

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return StreamBuilder<Reading>(
      stream: _stream,
      builder: (context, snap) {
        final failed = snap.hasError;
        return Column(children: [
          Expanded(
            flex: 3,
            child: _Panel(
              child: failed ? widget.instrument.buildError(context, snap.error!, _retry) : widget.instrument.buildLive(context, snap.data),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(flex: 1, child: _Panel(child: widget.instrument.buildDetail(context, snap.data))),
          const SizedBox(height: 8),
          _RecordingBar(instrument: widget.instrument, registry: widget.registry, recorder: widget.recorder, enabled: !failed),
          const SizedBox(height: 8),
          Container(height: 12, decoration: BoxDecoration(color: orc.panel, borderRadius: BorderRadius.circular(orc.railRadius))),
        ]);
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: orc.panel), borderRadius: BorderRadius.circular(orc.railRadius)),
      child: Center(child: child),
    );
  }
}

class _RecordingBar extends StatefulWidget {
  const _RecordingBar({required this.instrument, required this.registry, required this.recorder, required this.enabled});
  final Instrument instrument;
  final Registry registry;
  final Recorder recorder;
  final bool enabled;

  @override
  State<_RecordingBar> createState() => _RecordingBarState();
}

class _RecordingBarState extends State<_RecordingBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool get _mine => widget.recorder.recording && widget.recorder.instrument == widget.instrument;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.recorder, widget.registry]),
      builder: (context, _) {
        final elapsed = _mine ? DateTime.now().difference(widget.recorder.startedAt!) : Duration.zero;
        final mm = elapsed.inMinutes.toString().padLeft(2, '0');
        final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
        final logging = widget.instrument.canLog && widget.registry.isLogging(widget.instrument.id);
        return Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: orc.panel, borderRadius: BorderRadius.circular(orc.railRadius)),
          child: Row(children: [
            IconButton(
              key: const Key('record'),
              onPressed: widget.enabled ? () => _mine ? widget.recorder.stop() : widget.recorder.start(widget.instrument) : null,
              icon: Icon(_mine ? Icons.stop_circle : Icons.fiber_manual_record, color: Theme.of(context).colorScheme.error),
              iconSize: 32,
            ),
            Text('$mm:$ss', style: Theme.of(context).textTheme.titleMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont)),
            const Spacer(),
            if (widget.recorder.error != null && widget.recorder.instrument == widget.instrument)
              Flexible(child: Text(widget.recorder.error!, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (logging)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: orc.accent), borderRadius: BorderRadius.circular(12)),
                child: Text(widget.instrument.logSummary(widget.registry.settingsFor(widget.instrument)), style: TextStyle(color: orc.accent, fontFamily: orc.displayFont)),
              ),
          ]),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze --fatal-infos && flutter test test/shell/instrument_screen_test.dart test/skins/skins_test.dart`
Expected: PASS. Each test ends by pumping an empty widget so the recording bar's periodic timer is disposed — flutter_test fails a test that leaves a timer pending.

- [ ] **Step 5: Commit**

```bash
git add lib/shell/instrument_screen.dart test/shell/instrument_screen_test.dart
git commit -m "Instrument screen: live/detail bands, recording bar with session button and log chip

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 9: Motion instrument

**Files:**
- Create: `lib/instruments/sensor_util.dart`, `lib/instruments/motion.dart`, `test/instruments/sensor_util_test.dart`, `test/instruments/motion_test.dart`

**Interfaces:**
- Produces:
  - `Future<bool> firstEventWithin<T>(Stream<T> s, Duration d)` — true if an event arrives in time
  - `Stream<(A, B)> merge2<A, B>(Stream<A> a, Stream<B> b)` — emits on every `a` event once both have a latest value
  - `class MotionInstrument extends Instrument { MotionInstrument({Stream<AccelerometerEvent>? accel, Stream<GyroscopeEvent>? gyro}) }` — id `motion`; readings `{ax, ay, az, gx, gy, gz, g, pitch, roll}`
  - `({double pitch, double roll}) tilt(double ax, double ay, double az)` — degrees
- Consumes: `Instrument` (1), `OrcTheme` (6).

- [ ] **Step 1: Write the failing tests**

`test/instruments/sensor_util_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/sensor_util.dart';

void main() {
  test('firstEventWithin: true on an event, false on silence, false on error', () async {
    expect(await firstEventWithin(Stream.value(1), const Duration(milliseconds: 50)), isTrue);
    expect(await firstEventWithin(StreamController<int>().stream, const Duration(milliseconds: 20)), isFalse);
    expect(await firstEventWithin(Stream<int>.error(StateError('x')), const Duration(milliseconds: 50)), isFalse);
  });

  test('merge2 emits on a-events once b has a value, carrying the latest b', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final out = <(int, String)>[];
    final sub = merge2(a.stream, b.stream).listen(out.add);
    a.add(1); // no b yet: nothing
    await Future<void>.delayed(Duration.zero);
    b.add('x');
    a.add(2);
    b.add('y');
    a.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(out, [(2, 'x'), (3, 'y')]);
    await sub.cancel();
    expect(a.hasListener, isFalse, reason: 'cancel propagates');
  });
}
```

`test/instruments/motion_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/instruments/`
Expected: FAIL — both `Target of URI doesn't exist`.

- [ ] **Step 3: Write the helpers and the instrument**

`lib/instruments/sensor_util.dart`:

```dart
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
```

`lib/instruments/motion.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'sensor_util.dart';

const _g0 = 9.80665;

/// Pitch (nose up, +) and roll (right side down, +) in degrees from gravity.
({double pitch, double roll}) tilt(double ax, double ay, double az) => (
      pitch: atan2(ay, sqrt(ax * ax + az * az)) * 180 / pi,
      roll: atan2(ax, az) * 180 / pi,
    );

class MotionInstrument extends Instrument {
  MotionInstrument({Stream<AccelerometerEvent>? accel, Stream<GyroscopeEvent>? gyro})
      : _accel = accel ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
        _gyro = gyro ?? gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval);

  final Stream<AccelerometerEvent> _accel;
  final Stream<GyroscopeEvent> _gyro;

  @override
  String get id => 'motion';
  @override
  String get name => 'Motion';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() => firstEventWithin(_accel, const Duration(seconds: 2));

  @override
  Stream<Reading> live() => merge2(_accel, _gyro).map((e) {
        final (a, w) = e;
        final t = tilt(a.x, a.y, a.z);
        return Reading(DateTime.now(), {
          'ax': a.x, 'ay': a.y, 'az': a.z,
          'gx': w.x, 'gy': w.y, 'gz': w.z,
          'g': sqrt(a.x * a.x + a.y * a.y + a.z * a.z) / _g0,
          'pitch': t.pitch, 'roll': t.roll,
        });
      });

  @override
  Future<Reading> sample() => live().first;

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 160,
        height: 160,
        child: CustomPaint(painter: _LevelPainter(pitch: r?.values['pitch']?.toDouble() ?? 0, roll: r?.values['roll']?.toDouble() ?? 0, accent: orc.accent, ring: orc.panel)),
      ),
      const SizedBox(height: 12),
      Text(r == null ? '—' : '${r.values['g']!.toStringAsFixed(3)} g', style: big),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => _Grid({
        'Pitch': _deg(r?.values['pitch']),
        'Roll': _deg(r?.values['roll']),
        'Accel': _xyz(r, 'ax', 'ay', 'az', 'm/s²'),
        'Gyro': _xyz(r, 'gx', 'gy', 'gz', 'rad/s'),
      });

  String _deg(num? v) => v == null ? '—' : '${v.toStringAsFixed(1)}°';
  String _xyz(Reading? r, String x, String y, String z, String unit) =>
      r == null ? '—' : '${r.values[x]!.toStringAsFixed(2)} ${r.values[y]!.toStringAsFixed(2)} ${r.values[z]!.toStringAsFixed(2)} $unit';
}

/// A bubble level: the bubble moves opposite to the tilt, clamped to the ring.
class _LevelPainter extends CustomPainter {
  _LevelPainter({required this.pitch, required this.roll, required this.accent, required this.ring});
  final double pitch, roll;
  final Color accent, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rr = size.width / 2 - 4;
    canvas.drawCircle(c, rr, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawCircle(c, 10, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 1);
    final scale = rr / 45; // 45° reaches the ring
    final off = Offset((-roll * scale).clamp(-rr, rr), (pitch * scale).clamp(-rr, rr));
    canvas.drawCircle(c + off, 12, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_LevelPainter o) => o.pitch != pitch || o.roll != roll || o.accent != accent;
}

/// Label/value pairs, two per row — shared shape for every detail band.
class _Grid extends StatelessWidget {
  const _Grid(this.items);
  final Map<String, String> items;
  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final e in items.entries)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${orc.text(e.key)}  ', style: style.copyWith(color: style.color!.withValues(alpha: 0.6))),
            TextSpan(text: e.value, style: style),
          ])),
      ],
    );
  }
}
```

Move `_Grid` to `lib/instruments/detail_grid.dart` as a public `DetailGrid` once the compass needs it (Task 10) — do it there, not now.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test test/instruments/ test/skins/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/instruments test/instruments
git commit -m "Motion instrument: accelerometer + gyro, bubble level, tilt

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 10: Compass instrument

**Files:**
- Create: `lib/instruments/compass.dart`, `lib/instruments/detail_grid.dart`, `test/instruments/compass_test.dart`
- Modify: `lib/instruments/motion.dart` (use `DetailGrid`)

**Interfaces:**
- Produces:
  - `double headingDegrees({required double ax, ay, az, mx, my, mz})` — 0..360, magnetic, tilt-compensated
  - `String cardinal(double deg)` — N, NE, …
  - `class CompassInstrument extends Instrument { CompassInstrument({Stream<AccelerometerEvent>? accel, Stream<MagnetometerEvent>? mag}) }` — id `compass`; readings `{heading, field, mx, my, mz}`
  - `class DetailGrid extends StatelessWidget { DetailGrid(Map<String, String>) }`

- [ ] **Step 1: Write the failing test**

`test/instruments/compass_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/instruments/compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  // Phone flat (gravity on +z). Earth's field: horizontal component plus a
  // downward component; the horizontal part points to magnetic north.
  test('heading: north along +y is 0°, north along +x is 270°, along -y is 180°', () {
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 0, my: 20, mz: -40), closeTo(0, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 20, my: 0, mz: -40), closeTo(270, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 0, my: -20, mz: -40), closeTo(180, 0.01));
    expect(headingDegrees(ax: 0, ay: 0, az: 9.8, mx: -20, my: 0, mz: -40), closeTo(90, 0.01));
  });

  test('heading is tilt-compensated: pitching the phone up does not change it', () {
    final flat = headingDegrees(ax: 0, ay: 0, az: 9.8, mx: 14.1, my: 14.1, mz: -40);
    // Rotate both vectors about x by 30°: (x, y, z) → (x, y·c − z·s, y·s + z·c).
    const c = 0.8660254, s = 0.5;
    final tilted = headingDegrees(ax: 0, ay: -9.8 * s, az: 9.8 * c, mx: 14.1, my: 14.1 * c + 40 * s, mz: 14.1 * s - 40 * c);
    expect(tilted, closeTo(flat, 0.5));
  });

  test('cardinal', () {
    expect(cardinal(0), 'N');
    expect(cardinal(247), 'WSW');
    expect(cardinal(359), 'N');
  });

  test('live reading carries heading and field strength in µT', () async {
    final accel = StreamController<AccelerometerEvent>();
    final mag = StreamController<MagnetometerEvent>();
    final c = CompassInstrument(accel: accel.stream, mag: mag.stream);
    final first = c.live().first;
    accel.add(AccelerometerEvent(0, 0, 9.8, DateTime(2026)));
    mag.add(MagnetometerEvent(0, 30, -40, DateTime(2026)));
    accel.add(AccelerometerEvent(0, 0, 9.8, DateTime(2026)));
    final r = await first;
    expect(r.values['heading'], closeTo(0, 0.01));
    expect(r.values['field'], closeTo(50, 0.01));
    expect(c.id, 'compass');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/instruments/compass_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write DetailGrid, the compass, and switch motion to DetailGrid**

`lib/instruments/detail_grid.dart` — move `_Grid` out of `motion.dart`, renamed `DetailGrid`, public constructor `const DetailGrid(this.items)`; otherwise identical. Replace `_Grid(` with `DetailGrid(` in `motion.dart` and add `import 'detail_grid.dart';`.

`lib/instruments/compass.dart`:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'sensor_util.dart';

/// Android's getRotationMatrix + getOrientation, reduced to the azimuth:
/// H = E × A (east), M = A × H (north); azimuth = atan2(Hy, My).
double headingDegrees({required double ax, required double ay, required double az, required double mx, required double my, required double mz}) {
  var hx = my * az - mz * ay, hy = mz * ax - mx * az, hz = mx * ay - my * ax;
  final hn = sqrt(hx * hx + hy * hy + hz * hz);
  if (hn == 0) return 0;
  hx /= hn; hy /= hn; hz /= hn;
  final an = sqrt(ax * ax + ay * ay + az * az);
  final nx = ax / an, ny = ay / an, nz = az / an;
  final my_ = nz * hx - nx * hz; // M = A × H, y component
  final deg = atan2(hy, my_) * 180 / pi;
  return (deg + 360) % 360;
}

const _points = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
String cardinal(double deg) => _points[((deg + 11.25) % 360 ~/ 22.5)];

class CompassInstrument extends Instrument {
  CompassInstrument({Stream<AccelerometerEvent>? accel, Stream<MagnetometerEvent>? mag})
      : _accel = accel ?? accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval),
        _mag = mag ?? magnetometerEventStream(samplingPeriod: SensorInterval.uiInterval);

  final Stream<AccelerometerEvent> _accel;
  final Stream<MagnetometerEvent> _mag;

  @override
  String get id => 'compass';
  @override
  String get name => 'Compass';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() => firstEventWithin(_mag, const Duration(seconds: 2));

  @override
  Stream<Reading> live() => merge2(_accel, _mag).map((e) {
        final (a, m) = e;
        return Reading(DateTime.now(), {
          'heading': headingDegrees(ax: a.x, ay: a.y, az: a.z, mx: m.x, my: m.y, mz: m.z),
          'field': sqrt(m.x * m.x + m.y * m.y + m.z * m.z),
          'mx': m.x, 'my': m.y, 'mz': m.z,
        });
      });

  @override
  Future<Reading> sample() => live().first;

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final h = r?.values['heading']?.toDouble();
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 180, height: 180, child: CustomPaint(painter: _DialPainter(heading: h ?? 0, accent: orc.accent, ring: orc.panel))),
      const SizedBox(height: 12),
      Text(h == null ? '—' : '${h.round()}°', style: big),
      Text(h == null ? '' : '${cardinal(h)} · ${orc.text('magnetic')}', style: TextStyle(color: orc.accent, fontFamily: orc.displayFont)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Field': r == null ? '—' : '${r.values['field']!.toStringAsFixed(1)} µT',
        'X Y Z': r == null ? '—' : '${r.values['mx']!.toStringAsFixed(1)} ${r.values['my']!.toStringAsFixed(1)} ${r.values['mz']!.toStringAsFixed(1)}',
      });
}

/// A rose that rotates so magnetic north stays north; the fixed lubber line is up.
class _DialPainter extends CustomPainter {
  _DialPainter({required this.heading, required this.accent, required this.ring});
  final double heading;
  final Color accent, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = ring..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-heading * pi / 180);
    final tick = Paint()..color = ring..strokeWidth = 2;
    for (var i = 0; i < 36; i++) {
      final len = i % 9 == 0 ? 16.0 : 8.0;
      canvas.drawLine(Offset(0, -r), Offset(0, -r + len), i == 0 ? (Paint()..color = accent..strokeWidth = 4) : tick);
      canvas.rotate(pi / 18);
    }
    canvas.restore();
    canvas.drawLine(Offset(c.dx, c.dy - r - 2), Offset(c.dx, c.dy - r + 24), Paint()..color = accent..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(_DialPainter o) => o.heading != heading || o.accent != accent;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test test/instruments/ test/skins/`
Expected: PASS. If the tilt test misses by more than 0.5°, the test's rotated vectors are wrong, not the formula — recompute them: rotating about x by θ maps (x, y, z) → (x, y·cosθ − z·sinθ, y·sinθ + z·cosθ), applied to both gravity (0, 0, 9.8) and field (14.1, 14.1, −40).

- [ ] **Step 5: Commit**

```bash
git add lib/instruments test/instruments
git commit -m "Compass instrument: tilt-compensated magnetic heading, rose dial

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 11: Location service and Location instrument

**Files:**
- Create: `lib/instruments/location_service.dart`, `lib/instruments/location.dart`, `test/instruments/location_test.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`

**Interfaces:**
- Produces:
  - `class LocationService` — `Future<Position> current({LocationAccuracy accuracy, Duration timeLimit})`, `Stream<Position> stream()`, `Future<void> ensurePermission()`, `Future<bool> hasBackground()`, `Future<bool> requestBackground()`, `Future<void> openSettings()`; all overridable (tests subclass it)
  - `class LocationDenied implements Exception { String message }`
  - `class LocationInstrument extends Instrument { LocationInstrument(LocationService) }` — id `location`; readings `{lat, lon, alt, acc, speed}`; `canLog` = `Platform.isAndroid`; `logPrecondition()` non-null unless background permission is granted
- Consumes: `Instrument` (1), `DetailGrid` (10), `OrcTheme` (6).

- [ ] **Step 1: Write the failing test**

`test/instruments/location_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/instruments/location.dart';
import 'package:orctool/instruments/location_service.dart';
import 'package:orctool/skins/all.dart';

class FakeLocation extends LocationService {
  FakeLocation({this.permitted = true, this.background = false});
  bool permitted, background;
  static final pos = Position(latitude: 51.5, longitude: -0.12, timestamp: DateTime(2026, 9, 13), accuracy: 5, altitude: 312, altitudeAccuracy: 3, heading: 0, headingAccuracy: 0, speed: 1.2, speedAccuracy: 0.5);

  @override
  Future<void> ensurePermission() async {
    if (!permitted) throw LocationDenied('Location permission needed');
  }
  @override
  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    await ensurePermission();
    return pos;
  }
  @override
  Stream<Position> stream() async* {
    await ensurePermission();
    yield pos;
  }
  @override
  Future<bool> hasBackground() async => background;
}

void main() {
  test('reading columns', () async {
    final r = await LocationInstrument(FakeLocation()).sample();
    expect(r.values, {'lat': 51.5, 'lon': -0.12, 'alt': 312, 'acc': 5, 'speed': 1.2});
    expect(r.ts, DateTime(2026, 9, 13));
  });

  test('live surfaces the denial as a stream error', () {
    expect(LocationInstrument(FakeLocation(permitted: false)).live().first, throwsA(isA<LocationDenied>()));
  });

  test('logPrecondition needs background permission', () async {
    expect(await LocationInstrument(FakeLocation(background: false)).logPrecondition(), contains('all the time'));
    expect(await LocationInstrument(FakeLocation(background: true)).logPrecondition(), isNull);
  });

  testWidgets('error band offers Retry and App settings', (t) async {
    var retried = false;
    final i = LocationInstrument(FakeLocation());
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: Builder(builder: (c) => i.buildError(c, LocationDenied('Location permission needed'), () => retried = true)))));
    expect(find.text('Location permission needed'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    await t.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  test('default log settings are hourly with high accuracy; sample honours a low setting', () async {
    final i = LocationInstrument(FakeLocation());
    expect(i.defaultLogSettings.interval, LogInterval.hourly);
    expect(i.defaultLogSettings.extra['accuracy'], 'high');
    final seen = <LocationAccuracy>[];
    final svc = _RecordingLocation(seen);
    final j = LocationInstrument(svc);
    j.log = const LogSettings(extra: {'accuracy': 'low'});
    await j.sample();
    expect(seen, [LocationAccuracy.low]);
  });
}

class _RecordingLocation extends FakeLocation {
  _RecordingLocation(this.seen);
  final List<LocationAccuracy> seen;
  @override
  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    seen.add(accuracy);
    return FakeLocation.pos;
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/instruments/location_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the service and the instrument**

`lib/instruments/location_service.dart`:

```dart
import 'package:geolocator/geolocator.dart';

class LocationDenied implements Exception {
  LocationDenied(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The one place geolocator is called. Location and Weather share it.
class LocationService {
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw LocationDenied('Location is turned off on this phone');
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
    if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw LocationDenied('Location permission needed');
  }

  Future<Position> current({LocationAccuracy accuracy = LocationAccuracy.high, Duration timeLimit = const Duration(seconds: 30)}) async {
    await ensurePermission();
    return Geolocator.getCurrentPosition(locationSettings: LocationSettings(accuracy: accuracy, timeLimit: timeLimit));
  }

  Stream<Position> stream() async* {
    await ensurePermission();
    yield* Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
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
```

`lib/instruments/location.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'location_service.dart';

class LocationInstrument extends Instrument {
  LocationInstrument(this._svc);
  final LocationService _svc;

  @override
  String get id => 'location';
  @override
  String get name => 'Location';

  /// iOS stays false until an "Always" authorisation flow exists (spec §4).
  @override
  bool get canLog => Platform.isAndroid;

  @override
  Duration get sampleTimeout => const Duration(seconds: 60);

  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<Reading> live() => _svc.stream().map(_reading);

  @override
  Future<Reading> sample() async => _reading(await _svc.current(accuracy: _accuracy(log), timeLimit: const Duration(seconds: 45)));

  @override
  LogSettings get defaultLogSettings => const LogSettings(extra: {'accuracy': 'high'});

  LocationAccuracy _accuracy(LogSettings s) => s.extra['accuracy'] == 'low' ? LocationAccuracy.low : LocationAccuracy.high;

  Reading _reading(Position p) => Reading(p.timestamp, {'lat': p.latitude, 'lon': p.longitude, 'alt': p.altitude, 'acc': p.accuracy, 'speed': p.speed});

  @override
  Future<String?> logPrecondition() async => await _svc.hasBackground() ? null : 'Location must be allowed "all the time" — open Details';

  @override
  String logSummary(LogSettings s) => 'Log: ${s.interval.label} · ${s.extra['accuracy'] ?? 'high'}';

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.headlineMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    if (r == null) return Text('—', style: big);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${r.values['lat']!.toStringAsFixed(5)}, ${r.values['lon']!.toStringAsFixed(5)}', style: big),
      const SizedBox(height: 8),
      Text('${r.values['alt']!.toStringAsFixed(0)} m ${orc.text('altitude')}', style: big.copyWith(fontSize: big.fontSize! * 0.8)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Accuracy': r == null ? '—' : '±${r.values['acc']!.toStringAsFixed(0)} m',
        'Speed': r == null ? '—' : '${r.values['speed']!.toStringAsFixed(1)} m/s',
        'Fix at': r == null ? '—' : TimeOfDay.fromDateTime(r.ts.toLocal()).format(context),
      });

  @override
  Widget buildError(BuildContext context, Object error, VoidCallback retry) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$error', textAlign: TextAlign.center),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: retry, child: const Text('Retry')),
          TextButton(onPressed: _svc.openSettings, child: const Text('App settings')),
        ]),
      ]);

  /// The prominent disclosure Play requires before the system prompt (spec §4).
  @override
  Widget buildLogSettings(BuildContext context, LogSettings current, ValueChanged<LogSettings> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: current.extra['accuracy'] as String? ?? 'high',
        decoration: const InputDecoration(labelText: 'Accuracy'),
        items: const [DropdownMenuItem(value: 'high', child: Text('High (GPS)')), DropdownMenuItem(value: 'low', child: Text('Low (network)'))],
        onChanged: (v) => onChanged(current.copyWith(extra: {...current.extra, 'accuracy': v})),
      ),
      const SizedBox(height: 16),
      const Text('Logging location while the app is closed needs location access "all the time". '
          'Orctool records your position on the schedule above, keeps it only on this phone, and never sends it anywhere.'),
      const SizedBox(height: 8),
      FutureBuilder<bool>(
        future: _svc.hasBackground(),
        builder: (context, snap) => FilledButton(
          onPressed: snap.data == true ? null : () async {
            await _svc.requestBackground();
            onChanged(current); // re-render the precondition
          },
          child: Text(snap.data == true ? 'Allowed all the time' : 'Allow all the time'),
        ),
      ),
    ]);
  }
}
```

Manifest — add inside `<manifest>` of `android/app/src/main/AndroidManifest.xml`, before `<application>`:

```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

`ios/Runner/Info.plist` — add inside the top-level `<dict>`:

```xml
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Orctool shows your position, altitude and local weather.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Orctool can log your position on a schedule while it is closed; the log stays on this device.</string>
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test test/instruments/ test/skins/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/instruments/location_service.dart lib/instruments/location.dart test/instruments/location_test.dart android/app/src/main/AndroidManifest.xml ios/Runner/Info.plist
git commit -m "Location instrument and shared LocationService; permissions declared

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 12: Weather instrument (Open-Meteo)

**Files:**
- Create: `lib/instruments/weather.dart`, `test/instruments/weather_test.dart`

**Interfaces:**
- Produces:
  - `class WeatherInstrument extends Instrument { WeatherInstrument(LocationService, {http.Client? client, Duration refresh = 15 min}) }` — id `weather`; readings `{temp, humidity, pressure, wind, wind_dir, code, lat, lon}`
  - `String describeWmo(int code)`
- Consumes: `LocationService` (11), `DetailGrid` (10).

- [ ] **Step 1: Write the failing test**

`test/instruments/weather_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:orctool/instruments/weather.dart';

import 'location_test.dart' show FakeLocation;

const _body = '{"latitude":51.49,"longitude":-0.13,"current_units":{"temperature_2m":"°C"},'
    '"current":{"time":"2026-09-14T02:15","interval":900,"temperature_2m":19.3,"relative_humidity_2m":94,'
    '"surface_pressure":1022.3,"wind_speed_10m":7.9,"wind_direction_10m":235,"weather_code":3}}';

void main() {
  test('sample asks Open-Meteo for the current conditions at the phone position', () async {
    Uri? seen;
    final client = MockClient((req) async {
      seen = req.url;
      return http.Response(_body, 200);
    });
    final r = await WeatherInstrument(FakeLocation(), client: client).sample();
    expect(seen!.host, 'api.open-meteo.com');
    expect(seen!.queryParameters['latitude'], '51.5');
    expect(seen!.queryParameters['current'], contains('temperature_2m'));
    expect(r.values['temp'], 19.3);
    expect(r.values['humidity'], 94);
    expect(r.values['pressure'], 1022.3);
    expect(r.values['wind'], 7.9);
    expect(r.values['wind_dir'], 235);
    expect(r.values['code'], 3);
    expect(r.values['lat'], 51.5);
  });

  test('a non-200 or malformed response is an error, not a reading', () {
    final bad = MockClient((_) async => http.Response('nope', 503));
    expect(WeatherInstrument(FakeLocation(), client: bad).sample(), throwsException);
    final junk = MockClient((_) async => http.Response(jsonEncode({'x': 1}), 200));
    expect(WeatherInstrument(FakeLocation(), client: junk).sample(), throwsA(anything));
  });

  test('live keeps the last reading when a refresh fails', () async {
    var calls = 0;
    final client = MockClient((_) async => ++calls == 1 ? http.Response(_body, 200) : http.Response('', 500));
    final w = WeatherInstrument(FakeLocation(), client: client, refresh: const Duration(milliseconds: 10));
    final two = await w.live().take(2).toList();
    expect(two[1].values['temp'], 19.3);
    expect(two[1].ts, two[0].ts, reason: 'age is visible: the timestamp did not move');
  });

  test('describeWmo', () {
    expect(describeWmo(0), 'Clear');
    expect(describeWmo(3), 'Overcast');
    expect(describeWmo(61), 'Rain');
    expect(describeWmo(95), 'Thunderstorm');
    expect(describeWmo(42), 'Code 42');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/instruments/weather_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the instrument**

`lib/instruments/weather.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../core/instrument.dart';
import '../skins/skin.dart';
import 'detail_grid.dart';
import 'location_service.dart';

const _fields = 'temperature_2m,relative_humidity_2m,surface_pressure,wind_speed_10m,wind_direction_10m,weather_code';

String describeWmo(int code) => switch (code) {
      0 => 'Clear',
      1 => 'Mostly clear',
      2 => 'Partly cloudy',
      3 => 'Overcast',
      45 || 48 => 'Fog',
      >= 51 && <= 57 => 'Drizzle',
      >= 61 && <= 67 => 'Rain',
      >= 71 && <= 77 => 'Snow',
      >= 80 && <= 82 => 'Showers',
      85 || 86 => 'Snow showers',
      >= 95 && <= 99 => 'Thunderstorm',
      _ => 'Code $code',
    };

/// Open-Meteo, no key. Sends the phone's approximate position (spec §4).
class WeatherInstrument extends Instrument {
  WeatherInstrument(this._loc, {http.Client? client, this.refresh = const Duration(minutes: 15)}) : _client = client ?? http.Client();
  final LocationService _loc;
  final http.Client _client;
  final Duration refresh;

  @override
  String get id => 'weather';
  @override
  String get name => 'Weather';
  @override
  bool get canLog => true;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Reading> sample() async {
    final p = await _loc.current(accuracy: LocationAccuracy.low, timeLimit: const Duration(seconds: 20));
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {'latitude': '${p.latitude}', 'longitude': '${p.longitude}', 'current': _fields});
    final res = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Weather service returned ${res.statusCode}');
    final cur = ((jsonDecode(res.body) as Map)['current'] as Map).cast<String, Object?>();
    return Reading(DateTime.now(), {
      'temp': cur['temperature_2m'] as num,
      'humidity': cur['relative_humidity_2m'] as num,
      'pressure': cur['surface_pressure'] as num,
      'wind': cur['wind_speed_10m'] as num,
      'wind_dir': cur['wind_direction_10m'] as num,
      'code': cur['weather_code'] as num,
      'lat': p.latitude,
      'lon': p.longitude,
    });
  }

  /// First fetch, then every [refresh]; a failed refresh re-emits the last reading (its age shows).
  @override
  Stream<Reading> live() async* {
    Reading last = await sample();
    yield last;
    await for (final _ in Stream<void>.periodic(refresh)) {
      try {
        last = await sample();
      } catch (_) {
        // Spec §5: show the last reading with its age rather than an error.
      }
      yield last;
    }
  }

  @override
  Widget buildLive(BuildContext context, Reading? r) {
    final orc = OrcTheme.of(context);
    final big = Theme.of(context).textTheme.displayMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    if (r == null) return Text('—', style: big);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('${r.values['temp']!.toStringAsFixed(1)} °C', style: big),
      Text(orc.text(describeWmo(r.values['code']!.toInt())), style: TextStyle(color: orc.accent, fontFamily: orc.displayFont, fontSize: 18)),
      Text('${orc.text('as of')} ${TimeOfDay.fromDateTime(r.ts.toLocal()).format(context)}', style: TextStyle(color: orc.accent.withValues(alpha: 0.6), fontFamily: orc.displayFont)),
    ]);
  }

  @override
  Widget buildDetail(BuildContext context, Reading? r) => DetailGrid({
        'Humidity': r == null ? '—' : '${r.values['humidity']} %',
        'Pressure': r == null ? '—' : '${r.values['pressure']} hPa',
        'Wind': r == null ? '—' : '${r.values['wind']} km/h @ ${r.values['wind_dir']}°',
      });
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test test/instruments/ test/skins/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/instruments/weather.dart test/instruments/weather_test.dart
git commit -m "Weather instrument: Open-Meteo current conditions, keeps last reading on failure

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 13: Records screen and CSV export

**Files:**
- Create: `lib/core/csv.dart`, `lib/shell/records_screen.dart`, `test/core/csv_test.dart`, `test/shell/records_screen_test.dart`

**Interfaces:**
- Produces:
  - `String toCsv(List<Map<String, Object?>> rows)` — `ts` first (ISO-8601), then the union of other keys sorted; values quoted when they contain `,` `"` or newline
  - `class RecordsScreen extends StatefulWidget { RecordsScreen({store, registry, prefs}) }`
  - `class RunScreen extends StatelessWidget { RunScreen({store, run: RunSummary, share: Future<void> Function(String csv, String filename)}) }`
  - `Future<void> shareCsv(String csv, String filename)` — writes to the temp dir and opens the share sheet
- Consumes: `Store`, `RunSummary` (2), `Registry` (4), `Prefs` (3), `OrcTheme` (6).

- [ ] **Step 1: Write the failing tests**

`test/core/csv_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/csv.dart';

void main() {
  test('ts first, union of keys sorted, quoting where needed', () {
    final csv = toCsv([
      {'ts': DateTime.utc(2026, 9, 13, 12), 'heading': 247.5, 'note': 'a,b'},
      {'ts': DateTime.utc(2026, 9, 13, 12, 0, 1), 'field': 48.2, 'note': 'say "hi"'},
    ]);
    expect(csv.split('\n'), [
      'ts,field,heading,note',
      '2026-09-13T12:00:00.000Z,,247.5,"a,b"',
      '2026-09-13T12:00:01.000Z,48.2,,"say ""hi"""',
    ]);
  });

  test('empty', () => expect(toCsv([]), ''));
}
```

`test/shell/records_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/core/store.dart';
import 'package:orctool/shell/records_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

void main() {
  late Store store;
  late Registry reg;
  final t0 = DateTime(2026, 9, 13, 14, 2);

  setUp(() async {
    store = await memoryStore();
    final prefs = await memoryPrefs();
    reg = Registry([FakeInstrument(id: 'compass', name: 'Compass'), FakeInstrument(id: 'weather', name: 'Weather')], prefs, SpyScheduler());
    await reg.probe();
    await store.insert(instrument: 'compass', runId: 's1', kind: 'session', ts: t0, data: {'heading': 247}, limits: prefs.limits);
    await store.insert(instrument: 'compass', runId: 's1', kind: 'session', ts: t0.add(const Duration(seconds: 42)), data: {'heading': 248}, limits: prefs.limits);
    await store.insert(instrument: 'weather', runId: 'l1', kind: 'log', ts: t0.add(const Duration(hours: 1)), data: {'temp': 19.3}, limits: prefs.limits);
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: RecordsScreen(store: store, registry: reg, prefs: reg.prefs))));
    await t.pumpAndSettle();
  }

  testWidgets('lists runs newest first with instrument name, kind, rows; storage line', (t) async {
    await pump(t);
    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(find.descendant(of: tiles.first, matching: find.text('Weather')), findsOneWidget);
    expect(find.textContaining('Log ·'), findsOneWidget);
    expect(find.textContaining('Session ·'), findsOneWidget);
    expect(find.text('2 rows'), findsOneWidget);
    expect(find.textContaining('of 50 MB'), findsOneWidget);
  });

  testWidgets('filter chips', (t) async {
    await pump(t);
    await t.tap(find.text('Logs'));
    await t.pumpAndSettle();
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
  });

  testWidgets('tapping a run opens its table; share hands over CSV', (t) async {
    String? shared;
    await t.pumpWidget(MaterialApp(
      theme: skinById('plain').light,
      home: Scaffold(body: RecordsScreen(store: store, registry: reg, prefs: reg.prefs, share: (csv, name) async => shared = '$name\n$csv')),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Compass'));
    await t.pumpAndSettle();
    expect(find.text('247'), findsOneWidget);
    expect(find.text('248'), findsOneWidget);
    await t.tap(find.byIcon(Icons.share));
    await t.pumpAndSettle();
    expect(shared, startsWith('compass-s1.csv\nts,heading\n'));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/csv_test.dart test/shell/records_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist` for both.

- [ ] **Step 3: Write csv.dart and the screens**

`lib/core/csv.dart`:

```dart
/// Rows as Records stores them: {'ts': DateTime, ...columns}.
String toCsv(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return '';
  final keys = {for (final r in rows) ...r.keys}..remove('ts');
  final cols = ['ts', ...keys.toList()..sort()];
  String cell(Object? v) {
    final s = switch (v) { null => '', DateTime d => d.toUtc().toIso8601String(), _ => '$v' };
    return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
  }
  return [cols.join(','), for (final r in rows) cols.map((c) => cell(r[c])).join(',')].join('\n');
}
```

`lib/shell/records_screen.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/csv.dart';
import '../core/prefs.dart';
import '../core/registry.dart';
import '../core/store.dart';
import '../skins/skin.dart';

typedef ShareFn = Future<void> Function(String csv, String filename);

/// Writes the CSV to the temp dir and opens the platform share sheet.
Future<void> shareCsv(String csv, String filename) async {
  final f = File('${(await getTemporaryDirectory()).path}/$filename');
  await f.writeAsString(csv);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.store, required this.registry, required this.prefs, this.share = shareCsv});
  final Store store;
  final Registry registry;
  final Prefs prefs;
  final ShareFn share;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  String? _kind; // null = all

  String _name(String id) => widget.registry.byId(id)?.name ?? id;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final chipStyle = TextStyle(color: orc.accent, fontFamily: orc.displayFont);
    return Column(children: [
      Row(children: [
        for (final (k, label) in [(null, 'All'), ('session', 'Sessions'), ('log', 'Logs')])
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(label: Text(orc.text(label), style: chipStyle), selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
          ),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: FutureBuilder<List<RunSummary>>(
          future: widget.store.runs(kind: _kind),
          builder: (context, snap) {
            final runs = snap.data ?? const <RunSummary>[];
            if (snap.hasData && runs.isEmpty) return Center(child: Text(orc.text('Nothing recorded yet'), style: chipStyle));
            return ListView(children: [
              for (final r in runs)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(color: orc.panel, borderRadius: BorderRadius.circular(orc.railRadius), border: orc.railStripe ? Border(left: BorderSide(color: orc.accent, width: 4)) : null),
                  child: ListTile(
                    title: Text(orc.text(_name(r.instrument)), style: chipStyle.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('${r.kind == 'log' ? 'Log' : 'Session'} · ${_when(context, r)}', style: chipStyle.copyWith(color: orc.accent.withValues(alpha: 0.6))),
                    trailing: Text('${r.rows} rows', style: chipStyle),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunScreen(store: widget.store, run: r, title: _name(r.instrument), share: widget.share))),
                  ),
                ),
            ]);
          },
        ),
      ),
      const SizedBox(height: 8),
      FutureBuilder<int>(
        future: widget.store.totalBytes(),
        builder: (context, snap) => Text('${orc.text('Storage')}: ${_mb(snap.data ?? 0)} of ${_mb(widget.prefs.limits.capBytes)}', style: chipStyle),
      ),
    ]);
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 1024 * 1024 ? 2 : 0)} MB';

  String _when(BuildContext context, RunSummary r) {
    final d = r.last.difference(r.first);
    final span = d.inHours >= 1 ? '${d.inHours} h' : d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds} s';
    return '${MaterialLocalizations.of(context).formatShortDate(r.first)} ${TimeOfDay.fromDateTime(r.first).format(context)} · $span';
  }
}

class RunScreen extends StatelessWidget {
  const RunScreen({super.key, required this.store, required this.run, required this.title, required this.share});
  final Store store;
  final RunSummary run;
  final String title;
  final ShareFn share;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return Scaffold(
      backgroundColor: orc.ground,
      appBar: AppBar(backgroundColor: orc.accent, foregroundColor: orc.onAccent, title: Text(orc.text(title))),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: store.rows(run.runId),
        builder: (context, snap) {
          final rows = snap.data;
          if (rows == null) return const Center(child: CircularProgressIndicator());
          final cols = toCsv(rows).split('\n').first.split(',');
          return Column(children: [
            Expanded(
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [for (final c in cols) DataColumn(label: Text(c))],
                    rows: [
                      for (final r in rows)
                        DataRow(cells: [for (final c in cols) DataCell(Text(c == 'ts' ? TimeOfDay.fromDateTime((r['ts'] as DateTime).toLocal()).format(context) : '${r[c] ?? ''}'))]),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.icon(
                onPressed: () => share(toCsv(rows), '${run.instrument}-${run.runId}.csv'),
                icon: const Icon(Icons.share),
                label: const Text('Export CSV'),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test test/core/csv_test.dart test/shell/records_screen_test.dart test/skins/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/csv.dart lib/shell/records_screen.dart test/core/csv_test.dart test/shell/records_screen_test.dart
git commit -m "Records: runs list with filters and storage line, run table, CSV export via share sheet

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 14: Settings and the Instruments registry screen

**Files:**
- Create: `lib/shell/settings_screen.dart`, `lib/shell/instruments_screen.dart`, `test/shell/settings_test.dart`

**Interfaces:**
- Produces:
  - `class SettingsScreen extends StatelessWidget { SettingsScreen({prefs, registry}) }`
  - `class InstrumentsScreen extends StatelessWidget { InstrumentsScreen({registry}) }`
  - `class LogSettingsScreen extends StatefulWidget { LogSettingsScreen({registry, instrument}) }`
- Consumes: `Prefs` (3), `Registry` (4), `Instrument`, `LogSettings`, `LogInterval` (1), `skins` (6).

- [ ] **Step 1: Write the failing test**

`test/shell/settings_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/registry.dart';
import 'package:orctool/shell/settings_screen.dart';
import 'package:orctool/skins/all.dart';

import '../core/registry_test.dart' show SpyScheduler;
import '../fakes.dart';

class Blocked extends FakeInstrument {
  Blocked() : super(id: 'blocked', name: 'Blocked');
  @override
  Future<String?> logPrecondition() async => 'Needs a permission first';
}

void main() {
  late Registry reg;
  late SpyScheduler sched;

  setUp(() async {
    sched = SpyScheduler();
    reg = Registry([FakeInstrument(id: 'a', name: 'Alpha'), FakeInstrument(id: 'b', name: 'Beta', canLog: false), Blocked()], await memoryPrefs(), sched);
    await reg.probe();
  });

  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(theme: skinById('plain').light, home: Scaffold(body: SettingsScreen(prefs: reg.prefs, registry: reg))));
    await t.pumpAndSettle();
  }

  testWidgets('skin, retention and cap persist', (t) async {
    await pump(t);
    await t.tap(find.byKey(const Key('skin')));
    await t.pumpAndSettle();
    await t.tap(find.text('Console').last);
    await t.pumpAndSettle();
    expect(reg.prefs.skinId, 'console');
    await t.tap(find.byKey(const Key('retention')));
    await t.pumpAndSettle();
    await t.tap(find.text('90 days').last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('cap')));
    await t.pumpAndSettle();
    await t.tap(find.text('200 MB').last);
    await t.pumpAndSettle();
    expect(reg.prefs.limits.retentionDays, 90);
    expect(reg.prefs.limits.capBytes, 200 * 1024 * 1024);
  });

  testWidgets('Instruments: show toggle, log toggle only when canLog, precondition blocks logging', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('log-a')), findsOneWidget);
    expect(find.byKey(const Key('log-b')), findsNothing);
    await t.tap(find.byKey(const Key('show-b')));
    await t.pumpAndSettle();
    expect(reg.isShown('b'), isFalse);
    await t.tap(find.byKey(const Key('log-a')));
    await t.pumpAndSettle();
    expect(reg.isLogging('a'), isTrue);
    expect(sched.calls, ['schedule a 60']);
    await t.tap(find.byKey(const Key('log-blocked')));
    await t.pumpAndSettle();
    expect(reg.isLogging('blocked'), isFalse);
    expect(find.text('Needs a permission first'), findsOneWidget);
  });

  testWidgets('details page sets the interval', (t) async {
    await pump(t);
    await t.tap(find.text('Instruments'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('details-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('interval')));
    await t.pumpAndSettle();
    await t.tap(find.text('daily').last);
    await t.pumpAndSettle();
    expect(reg.settingsFor(reg.byId('a')!).interval, LogInterval.daily);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shell/settings_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the screens**

`lib/shell/settings_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/registry.dart';
import '../core/store.dart';
import '../skins/all.dart';
import '../skins/skin.dart';
import 'instruments_screen.dart';

const _retentionChoices = [7, 30, 90, 365];
const _capChoicesMb = [10, 50, 200, 1000];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.prefs, required this.registry});
  final Prefs prefs;
  final Registry registry;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(children: [
        DropdownButtonFormField<String>(
          key: const Key('skin'),
          initialValue: prefs.skinId,
          decoration: const InputDecoration(labelText: 'Skin'),
          items: [for (final s in skins) DropdownMenuItem(value: s.id, child: Text(s.name))],
          onChanged: (v) => prefs.setSkinId(v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const Key('retention'),
          initialValue: prefs.limits.retentionDays,
          decoration: const InputDecoration(labelText: 'Keep readings for'),
          items: [for (final d in _retentionChoices) DropdownMenuItem(value: d, child: Text('$d days'))],
          onChanged: (v) => prefs.setLimits(Limits(retentionDays: v!, capBytes: prefs.limits.capBytes)),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const Key('cap'),
          initialValue: prefs.limits.capBytes ~/ (1024 * 1024),
          decoration: const InputDecoration(labelText: 'Storage cap'),
          items: [for (final m in _capChoicesMb) DropdownMenuItem(value: m, child: Text('$m MB'))],
          onChanged: (v) => prefs.setLimits(Limits(retentionDays: prefs.limits.retentionDays, capBytes: v! * 1024 * 1024)),
        ),
        const SizedBox(height: 24),
        ListTile(
          tileColor: orc.panel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(orc.railRadius)),
          title: Text(orc.text('Instruments'), style: TextStyle(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold)),
          subtitle: Text('Order, show, logging', style: TextStyle(color: orc.accent.withValues(alpha: 0.6))),
          trailing: Icon(Icons.chevron_right, color: orc.accent),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => InstrumentsScreen(registry: registry))),
        ),
      ]),
    );
  }
}
```

`lib/shell/instruments_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../core/instrument.dart';
import '../core/registry.dart';
import '../skins/skin.dart';

/// The registry UI: drag to reorder the rail; show; log on/off; details ›.
class InstrumentsScreen extends StatelessWidget {
  const InstrumentsScreen({super.key, required this.registry});
  final Registry registry;

  Future<void> _toggleLog(BuildContext context, Instrument i, bool on) async {
    if (on) {
      final why = await i.logPrecondition();
      if (why != null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(why)));
        return;
      }
    }
    await registry.setLogging(i, on);
  }

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final style = TextStyle(color: orc.accent, fontFamily: orc.displayFont, fontWeight: FontWeight.bold);
    return Scaffold(
      backgroundColor: orc.ground,
      appBar: AppBar(backgroundColor: orc.accent, foregroundColor: orc.onAccent, title: Text(orc.text('Instruments'))),
      body: ListenableBuilder(
        listenable: registry,
        builder: (context, _) {
          final items = registry.ordered;
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            onReorder: registry.reorder,
            itemBuilder: (context, index) {
              final i = items[index];
              return Container(
                key: ValueKey(i.id),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: orc.panel, borderRadius: BorderRadius.circular(orc.railRadius)),
                child: ListTile(
                  leading: ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle, color: orc.accent)),
                  title: Text(orc.text(i.name), style: style),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Tooltip(message: 'Show', child: Switch.adaptive(key: Key('show-${i.id}'), value: registry.isShown(i.id), onChanged: (v) => registry.setShown(i.id, v))),
                    if (i.canLog) ...[
                      Tooltip(message: 'Log', child: Switch.adaptive(key: Key('log-${i.id}'), value: registry.isLogging(i.id), onChanged: (v) => _toggleLog(context, i, v))),
                      IconButton(
                        key: Key('details-${i.id}'),
                        icon: Icon(Icons.chevron_right, color: orc.accent),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LogSettingsScreen(registry: registry, instrument: i))),
                      ),
                    ],
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Interval (common) above the instrument's own details form.
class LogSettingsScreen extends StatefulWidget {
  const LogSettingsScreen({super.key, required this.registry, required this.instrument});
  final Registry registry;
  final Instrument instrument;

  @override
  State<LogSettingsScreen> createState() => _LogSettingsScreenState();
}

class _LogSettingsScreenState extends State<LogSettingsScreen> {
  late LogSettings _s = widget.registry.settingsFor(widget.instrument);

  Future<void> _update(LogSettings s) async {
    setState(() => _s = s);
    await widget.registry.setLogSettings(widget.instrument, s);
  }

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return Scaffold(
      backgroundColor: orc.ground,
      appBar: AppBar(backgroundColor: orc.accent, foregroundColor: orc.onAccent, title: Text(orc.text('${widget.instrument.name} log'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<LogInterval>(
          key: const Key('interval'),
          initialValue: _s.interval,
          decoration: const InputDecoration(labelText: 'Sample every'),
          items: [for (final v in LogInterval.values) DropdownMenuItem(value: v, child: Text(v.label))],
          onChanged: (v) => _update(_s.copyWith(interval: v)),
        ),
        const SizedBox(height: 8),
        const Text('Android may delay a scheduled sample to save battery; the gap shows in Records.'),
        const SizedBox(height: 16),
        widget.instrument.buildLogSettings(context, _s, _update),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze --fatal-infos && flutter test`
Expected: everything so far PASS. `Switch.adaptive` and `DropdownButtonFormField.initialValue` are the current API (Flutter 3.47); if analyze flags `initialValue` as unknown, the SDK is older than pinned — fix the SDK, not the code.

- [ ] **Step 5: Commit**

```bash
git add lib/shell/settings_screen.dart lib/shell/instruments_screen.dart test/shell/settings_test.dart
git commit -m "Settings (skin, retention, cap) and the Instruments registry screen with log details

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 15: Wire it up — main.dart, WorkManager, on-phone verification

**Files:**
- Create: `lib/instruments/all.dart`, `lib/scheduler_workmanager.dart`, `VERIFICATION.md`
- Modify: `lib/main.dart` (replace the template), `README.md` (replace the template)

**Interfaces:**
- Produces: `List<Instrument> allInstruments()`; `class WorkmanagerScheduler implements Scheduler`; `void callbackDispatcher()` (the `@pragma('vm:entry-point')` WorkManager entry).
- Consumes: everything above.

- [ ] **Step 1: Instruments list and the scheduler**

`lib/instruments/all.dart`:

```dart
import '../core/instrument.dart';
import 'compass.dart';
import 'location.dart';
import 'location_service.dart';
import 'motion.dart';
import 'weather.dart';

/// Registration order is the default rail order. Adding an instrument in a
/// later slice is one file plus one line here.
List<Instrument> allInstruments() {
  final loc = LocationService();
  return [MotionInstrument(), CompassInstrument(), LocationInstrument(loc), WeatherInstrument(loc)];
}
```

`lib/scheduler_workmanager.dart`:

```dart
import 'package:workmanager/workmanager.dart';

import 'core/registry.dart';

/// One periodic WorkManager task per instrument, named by its id. `update`
/// re-registers with the new interval instead of keeping the old one.
class WorkmanagerScheduler implements Scheduler {
  @override
  Future<void> schedule(String instrumentId, Duration every) => Workmanager().registerPeriodicTask(
        instrumentId,
        instrumentId,
        frequency: every,
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );

  @override
  Future<void> cancel(String instrumentId) => Workmanager().cancelByUniqueName(instrumentId);
}
```

- [ ] **Step 2: main.dart**

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import 'core/prefs.dart';
import 'core/recorder.dart';
import 'core/registry.dart';
import 'core/store.dart';
import 'instruments/all.dart';
import 'scheduler_workmanager.dart';
import 'shell/instrument_screen.dart';
import 'shell/records_screen.dart';
import 'shell/settings_screen.dart';
import 'shell/shell.dart';
import 'skins/all.dart';

Future<String> _dbPath() async => '${(await getApplicationDocumentsDirectory()).path}/readings.db';

/// WorkManager's entry point: runs in a background isolate with no UI. The
/// task name is the instrument id (WorkmanagerScheduler).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final i = allInstruments().where((i) => i.id == task).firstOrNull;
    if (i == null) return true;
    final prefs = await Prefs.open();
    final store = await Store.open(await _dbPath());
    try {
      await runScheduledSample(i, store, prefs);
    } finally {
      await store.close();
    }
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher);
  final prefs = await Prefs.open();
  final store = await Store.open(await _dbPath());
  final registry = Registry(allInstruments(), prefs, WorkmanagerScheduler());
  await registry.probe();
  runApp(OrctoolApp(prefs: prefs, store: store, registry: registry, recorder: Recorder(store, prefs)));
}

class OrctoolApp extends StatelessWidget {
  const OrctoolApp({super.key, required this.prefs, required this.store, required this.registry, required this.recorder});
  final Prefs prefs;
  final Store store;
  final Registry registry;
  final Recorder recorder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: prefs,
        builder: (context, _) {
          final skin = skinById(prefs.skinId);
          return MaterialApp(
            title: 'Orctool',
            theme: skin.light,
            darkTheme: skin.dark,
            themeMode: ThemeMode.system,
            home: Shell(
              registry: registry,
              recorder: recorder,
              prefs: prefs,
              store: store,
              instrumentBuilder: (_, i) => InstrumentScreen(key: ValueKey(i.id), instrument: i, registry: registry, recorder: recorder),
              recordsBuilder: (_) => RecordsScreen(store: store, registry: registry, prefs: prefs),
              settingsBuilder: (_) => SettingsScreen(prefs: prefs, registry: registry),
            ),
          );
        },
      );
}
```

- [ ] **Step 3: Analyze, test, run on the phone**

```bash
flutter analyze --fatal-infos && flutter test && flutter run
```

Expected: all tests pass; the app opens on the emulator (`-d emulator-5554`, started as in Task 0) in the plain skin with Motion selected; the bubble responds to the emulator's virtual accelerometer (Extended Controls → Virtual sensors). Take a screenshot (`adb exec-out screencap -p`) of each rail entry in both skins and put them in the report. `VERIFICATION.md` (next step) is walked on direflail's real phone.

- [ ] **Step 4: VERIFICATION.md — the on-phone checklist**

```markdown
# Verification — slice 1, on a real Android phone

Nothing in `flutter test` proves a sensor. Walk this after every change to an instrument
or to permissions, on the phone, and tick what you saw.

1. Launch: plain skin; rail shows Motion, Compass, Location, Weather, Records, Settings.
   Any instrument missing = its `isAvailable()` said no — check `adb logcat | grep -i sensor`.
2. Motion: tilt the phone; the bubble moves opposite to the tilt; `g` reads ~1.000 at rest.
3. Compass: rotate; heading changes smoothly; N on the dial points to magnetic north
   (compare with another compass app). Field reads 25–65 µT away from metal.
4. Location: first open asks for location permission → allow "while using". Lat/lon appear
   within a minute outdoors. Deny instead → the band says "Location permission needed" with
   Retry and App settings; the record button is disabled.
5. Weather: temperature and a condition appear; "as of" shows the fetch time. Airplane mode,
   then wait 15 min: the reading stays, the time does not move.
6. Session: record on Compass for 30 s, stop. Records lists it with rows > 0; open it; Export
   CSV opens the share sheet; the file has `ts,field,heading,mx,my,mz`.
7. Title bar: tap it; the rail slides in and "Compass" appears on the right; tap again; kill
   and relaunch — the rail state was remembered.
8. Skin: Settings → Console. Everything uppercase, Antonio, amber on black; back to Plain.
9. Settings → Instruments: drag Weather to the top — the rail follows. Hide Motion — it leaves
   the rail; unhide it.
10. Logging, Weather: Log on, details: every 15 min. Close the app fully. After ~20–30 min
    (Android may delay it), reopen: Records shows a Log run for Weather with ≥1 row.
11. Logging, Location: Log on → blocked with the "all the time" message. Details → Allow all
    the time → the system settings page; choose "Allow all the time"; back; Log on succeeds.
    Close the app; after the interval, Records shows a Location log row.
12. Retention: Settings → cap 10 MB; record Motion for 10 min; the storage line never exceeds
    10 MB.
13. Store rules: `flutter pub deps --style=compact` — the plugin list is what the Play Data
    safety form is answered from (location: collected, on-device; weather: approximate
    location sent to Open-Meteo).

Record the phone model and Android version with each run:

| Date | Phone | Android | Result |
|---|---|---|---|
```

- [ ] **Step 5: README**

Replace `README.md`:

```markdown
# Orctool

A tricorder-style instrument app for Android (and, later, iOS): the phone's real sensors and
free online services, presented as instruments, with recording. Skinnable.

Design: `docs/superpowers/specs/2026-09-13-orctool-slice-1-design.md`. Plan:
`docs/superpowers/plans/2026-09-13-orctool-slice-1.md`. On-phone checks: `VERIFICATION.md`.

    flutter analyze --fatal-infos && flutter test
    flutter run
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Wire the app: main, WorkManager scheduler and callback, on-phone verification checklist

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Walk VERIFICATION.md on the phone and record the result**

Fill the table row. Anything that fails is a bug in the instrument or permission flow: fix it (root cause, per `orclab:systematic-debugging` habits), re-run `flutter test`, commit, re-walk the affected item.

---

## Self-review

**Spec coverage** (each spec section → tasks):
- §1 architecture, contract, data flow, dependencies → Tasks 0, 1, 15; `buildError` and `logPrecondition` were added to the contract during planning (spec §5's error band and the "toggle snaps back off" behaviour needed a home).
- §2 table, sessions, logs, Records, retention, scheduling → Tasks 2, 4, 5, 13, 15.
- §3 shell, recording bar, Settings → Instruments, skins, live drawing → Tasks 6, 7, 8, 9, 10, 14.
- §4 permissions, manifest, Info.plist, background disclosure → Task 11 (the disclosure text lives in the Location details form); no exact alarms anywhere.
- §5 error handling → Tasks 5 (session/sample), 8 (error band, disabled bar), 11 (denied → settings), 12 (weather keeps last), 14 (precondition snaps back).
- §6 testing → every task; the "no literal colours" check is Task 6's test; on-phone checklist is Task 15.
- §7 not in slice → nothing here builds any of it.

**Known corners, deliberately cut** (each is a `ponytail:` comment or a note above): age-prune once a minute rather than per write (cap prune is still per write, so the spec's "at most one row over" holds); compass shows magnetic heading only — true north (declination) needs the World Magnetic Model and is slice 2; Records has no delete — retention is the only eraser; motion/compass `sample()` is `live().first`, which in the background isolate needs the sensor to deliver within `sampleTimeout` (30 s).

**Type consistency checked:** `Registry.prefs` is public (tests read `reg.prefs`); `Recorder.start` is sync, `stop` async; `Store.insert` named parameters match every caller; `LogSettings.extra` is `Map<String, Object?>` everywhere; `ShareFn` signature matches `shareCsv`; `Shell`'s three builders match `main.dart`.
