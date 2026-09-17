import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
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

Future<String> _dbPath() async => '${await getDatabasesPath()}/readings.db';

/// WorkManager's entry point: runs in a background isolate with no UI. The
/// task name is the instrument id (WorkmanagerScheduler).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await Prefs.open();
    final i = allInstruments(prefs).where((i) => i.id == task).firstOrNull;
    if (i == null) return true;
    final store = await Store.open(await _dbPath(), shared: false);
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
  final registry = Registry(allInstruments(prefs), prefs, WorkmanagerScheduler());
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
              settingsBuilder: (_) => SettingsScreen(prefs: prefs, registry: registry, store: store),
            ),
          );
        },
      );
}
