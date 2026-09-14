# Orctool — slice 1 design

*2026-09-13. Brainstormed with direflail; approved section by section. Background and the
Android/iOS availability table are in `docs/brainstorm-notes.md`.*

## What Orctool is

A cross-platform mobile app in the spirit of Moonblink's 2011 Android *Tricorder*: the phone's
real sensors and free online services, presented as instruments, with no fiction. Skinnable; one
skin is a "ship's console" look that is adjacent to LCARS, not a copy (the original was pulled
after a CBS takedown over exactly that). Instruments record, both as sessions while you watch and
on a schedule while the app is closed, with hard limits on how much is kept.

Stack: **Flutter**, per `/orc-code`'s Android + iOS row and `orclab:stack-flutter`. Android is
built and tested first (direflail has one Android phone); iOS is configured from day one but not
built until there is a reason to pay Apple.

## Slice 1 scope

Five slices are planned (skeleton; location + feeds; audio; radios; store onboarding). This spec
is slice 1: the skeleton with every shared mechanism, and four instruments chosen to cross each
permission tier once.

| Instrument | Exercises |
|---|---|
| Motion (accelerometer, gyro, level) | no permission |
| Compass (heading, magnetometer) | no permission; first realtime `CustomPainter` |
| Location (lat/lon/altitude) | foreground permission → background permission → Play declaration |
| Weather (Open-Meteo, no key) | network; a scheduled sample that works on every platform |

Scheduled sampling is **in** slice 1 on purpose: direflail wants to hit Play's policy friction
(and, later, Apple's) as early as possible, not defer it.

## 1. Architecture

Approach chosen: **instrument as a contract** (over feature-modules-per-instrument, and over
data-driven instruments). One abstract class; everything else is written once against it.

```
lib/
  main.dart                  app entry; builds registry, skin, shell
  core/
    instrument.dart          the Instrument contract + Reading
    registry.dart            list of instruments; availability probe; user order/show/log prefs
    recorder.dart            sessions (start/stop → rows) and scheduled sampling
    store.dart               sqflite: readings table, retention pruning, storage total
    prefs.dart               shared_preferences: rail state, skin, registry prefs, caps
  shell/
    shell.dart               title bar (tap toggles rail), sliding rail, content area
    records_screen.dart      sessions/logs list; entry → table + CSV share
    settings_screen.dart     skin, storage cap, retention, → Instruments
    instruments_screen.dart  registry UI: reorder, show, log, details ›
  skins/
    skin.dart                Skin = ThemeData + OrcTheme extension
    plain.dart, console.dart
  instruments/
    motion.dart, compass.dart, location.dart, weather.dart
```

### The Instrument contract

Every instrument is one file implementing:

| Member | Meaning |
|---|---|
| `id`, `name` | stable id (storage key), display name |
| `Future<bool> isAvailable()` | probed once at launch; false ⇒ not in the registry, not in any UI |
| `bool get canLog` | declared **in code, per platform**; false ⇒ no logging UI anywhere for it |
| `Stream<Reading> live()` | live values; consumed by the screen and by a running session |
| `Future<Reading> sample()` | one reading for the scheduler; may take seconds (GPS fix); has a declared timeout |
| `Widget buildLive(Reading)` | top band |
| `Widget buildDetail(Reading)` | middle band |
| `Widget buildLogSettings()` + defaults | the instrument-specific details form (interval is common; location may add accuracy/min-distance, motion a sample duration, weather which fields) |
| `String logSummary()` | one-line summary of current log settings, shown in the recording-bar chip |
| `Map<String, num> toRow(Reading)` | flat columns for storage and CSV |

Instruments that need each other (weather needs a position) share a service underneath; they do
not register differently. The rail is *registered instruments in user order, then Records, then
Settings* — those two fixed rows are the only non-instrument entries and have no readings.

### Data flow

- Live: sensor plugin → `live()` → `buildLive`/`buildDetail`; while a session runs, also →
  `recorder` → `store`.
- Scheduled: `workmanager` fires the task for one instrument → `sample()` → one row → `store`.
- Both paths write the same table.

### Dependencies

Kept short; each gets a live currency check (`orclab:currency-discipline`) at plan time.

| Need | Choice |
|---|---|
| State, navigation | Flutter's own `ChangeNotifier` + `Navigator`; no framework |
| Readings | `sqflite` (stack skill's decision) |
| Settings | `shared_preferences`, `SharedPreferencesWithCache` API (stack skill) |
| Accelerometer, gyro, magnetometer | `sensors_plus` |
| Compass heading | derive from `sensors_plus` magnetometer + accelerometer first; a rotation-vector plugin only if real-hardware testing shows the derivation is not good enough |
| Location | `geolocator` |
| HTTP | `http` |
| Scheduled work | `workmanager` (Android WorkManager now; iOS BGTaskScheduler later) |
| CSV export | the platform share sheet (`share_plus`) |

Before adding any plugin with native code: check it ships an iOS privacy manifest, is 16 KB-page
clean, and what it sends off-device (stack skill, "Choosing dependencies").

## 2. Data model and recording

One SQLite table:

```
readings(id INTEGER PRIMARY KEY, instrument TEXT, run_id TEXT, kind TEXT, ts INTEGER, data TEXT)
  kind ∈ {'session','log'};  data = toRow(reading) as JSON
  index (instrument, ts);  index (run_id)
```

- A **session** is a `run_id` created when the record button is pressed, closed when it is
  pressed again.
- A **log** is a `run_id` created when logging is turned on for an instrument; turning it off and
  on again starts a new one.
- **Records** lists distinct `run_id`s with instrument, kind, row count and time span; filter
  chips All / Sessions / Logs; storage total against the cap at the bottom. Tapping an entry shows
  a plain table (columns from the JSON keys) with a share button that exports CSV through the
  share sheet.
- **Retention**, run before every write: delete rows older than `retention_days` (default 30);
  then while `SUM(length(data))` exceeds `storage_cap` (default 50 MB) delete the oldest. Both
  values are in Settings. This is the whole limit system.
- **Scheduling**: per instrument with logging on, one `workmanager` periodic task named by the
  instrument id, interval from its details (15 min / hourly / daily — Android's floor is 15 min).
  The callback runs `sample()` and writes one row. Exact-time alarms are deliberately not used.

## 3. Shell and skins

**Shell.** Title bar across the top; rail on the left; content on the right.

- Title bar: app name on the left; when the rail is slid in, the current instrument's name fades
  in on the right. **Tapping anywhere on the title bar toggles the rail. Nothing else moves the
  rail** — selecting an instrument does not auto-hide it. Rail state is persisted.
- Rail: one segment per registered, shown instrument in the user's order; then Records; then
  Settings. Active segment is filled with the accent; the title bar shares that fill.
- Content: the selected instrument's three bands — live readout, detail strip, recording bar —
  or a shell screen.
- Recording bar (every instrument): record button + elapsed timer for sessions; a "Log: …" chip
  showing `logSummary()` only when logging is on for that instrument; nothing about logging at
  all when `canLog` is false.
- Back: on an instrument, nothing (the rail is the navigation); on Records/Settings sub-pages,
  pops.

**Settings → Instruments** (the registry UI): one row per registered instrument — drag handle ·
name · **show** · **log** on/off (absent when `canLog` is false) · **details ›** opening that
instrument's own `buildLogSettings()` form. Hidden instruments leave the rail and keep their
settings. Records and Settings always follow the last instrument. Storage cap and retention are on the main Settings page, not per
instrument.

**Skins.** `Skin { ThemeData theme; OrcTheme orc; }`, `OrcTheme` a `ThemeExtension` carrying what
Material lacks: rail segment radius and left-edge stripe, title-bar fill and on-fill colours,
accent, display typeface, uppercase flag. Widgets under `shell/` and `instruments/` read only
`Theme.of(context)` and `OrcTheme.of(context)`; no colour or radius literal lives outside
`skins/`. Two skins ship:

- `plain` — Material 3, follows the system light/dark. The default.
- `console` — near-black ground, one warm accent, uppercase condensed type in **Antonio** (OFL,
  bundled as an asset), rounded rail segments with a left stripe, filled title bar. No elbow
  frames, no multi-colour blocks, no LCARS palette. Never named "LCARS" anywhere.

Chosen in Settings, persisted, switches live.

**Live drawing.** Compass dial and the motion level are `CustomPainter`s repainting per stream
event; the stream is throttled to the display refresh rate.

## 4. Permissions and store rules

| Instrument | Android permission | Asked when | Play consequence |
|---|---|---|---|
| Motion, Compass | none | — | none |
| Weather | `INTERNET` | — | Data safety: approximate location is sent to Open-Meteo; privacy policy says so |
| Location, live/session | `ACCESS_FINE_LOCATION` | first open of the instrument | Data safety: location collected, kept on device |
| Location, log | `ACCESS_BACKGROUND_LOCATION` | when logging is turned on in its details page, after an in-app explanation screen (Play's prominent-disclosure rule) | background-location declaration + demo video at review |

Scheduled sampling needs no extra permission; battery optimisation may delay it and the details
page says so rather than fighting it.

iOS, carried by the contract now, built later: `canLog` is per platform, so Location's stays
false on iOS until an "Always"-authorisation flow exists; Weather's is true (`BGAppRefreshTask`).
The only iOS-specific work in slice 1 is the `NSLocationWhenInUseUsageDescription` /
`NSLocationAlwaysAndWhenInUseUsageDescription` strings in `Info.plist`.

Store paperwork this slice forces: a Play developer account, the 12-tester / 14-day closed test,
the Data safety form (answered from `flutter pub deps`), a hosted privacy policy, the
background-location declaration. All of it is `/orc-package play`; this project is what proves
that ingredient, and the Flutter stack skill with it.

## 5. Error handling

- Unavailable at launch → not registered; nothing to handle later.
- Permission denied → the live band shows one line and a button that re-asks or opens app
  settings; the recording bar is disabled. Background permission denied → the log toggle snaps
  back off with the same line on the details page.
- Sensor stream error → "no data" in the live band; a running session keeps its rows and stops
  cleanly.
- `sample()` fails in the background (no fix, no network, timeout) → no row, silently; the gap is
  visible in Records by timestamps. No retry; the next run is the retry.
- Store write fails → a session stops with a visible message; a scheduled sample is dropped.
  Retention runs before the write, so the cap is exceeded by at most one row.
- Weather request fails → the live band shows the last reading with its age ("as of 14:02");
  a scheduled sample writes nothing. One request, one timeout.

## 6. Testing

Per `orclab:test-discipline`: mock everything that leaves the process; 80% on what the slice
touches; prove each test can fail.

- **Contract tests**, one suite run against all four instruments: `toRow` is flat and JSON-safe;
  `sample()` completes within its declared timeout against a fake; `canLog` false ⇒ no log UI.
- **Recorder**: fake instrument with a scripted stream → a session writes exactly those rows
  under one `run_id`; the scheduled callback writes one row per invocation.
- **Store**: retention by age and by cap with realistic row sizes; storage total; Records
  queries.
- **Registry**: availability probe hides an instrument; order/show/log prefs round-trip; Records and Settings
  always follow the instruments.
- **Shell** (widget tests): title-bar tap toggles the rail; instrument name appears only when the
  rail is in; skin switch changes `OrcTheme`; no literal colours outside `skins/` (a lint or a
  grep test).
- **Instruments**, each with its plugin faked: compass heading from known magnetometer +
  accelerometer vectors; weather from a canned Open-Meteo response; location from a fixed
  position.
- **On the phone**: a short `VERIFICATION.md` — permission flows; a background sample lands after
  the interval; Data safety answers match the dependency list. Nothing above proves the sensors.

## 7. Not in this slice

Audio; Wi-Fi/cell; BLE; NFC; camera instruments; ruler; space weather and other feeds; the iOS
build (Codemagic) and App Store; charts of records (Records is a table + CSV); auto-hiding rail;
more than two skins; exact-time alarms.

## Decisions recorded along the way

- Android first; iOS configured now, built later.
- Recording is core: sessions and scheduled logs both in slice 1.
- Navigation: side rail (the original's structure), not a grid or a live dashboard.
- Skin distance: adjacent, not close — see §3 for what that means concretely.
- Logging is two-layered: `canLog` in code decides whether an instrument has logging at all;
  the interface then offers on/off plus an instrument-specific details form.
