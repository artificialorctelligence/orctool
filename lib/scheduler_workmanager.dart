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
