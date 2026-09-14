import 'package:flutter/widgets.dart';
import 'package:orctool/core/instrument.dart';
import 'package:orctool/core/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

Future<Store> memoryStore() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return Store.open(inMemoryDatabasePath);
}
