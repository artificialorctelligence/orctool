import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/registry.dart';
import '../core/store.dart';
import '../skins/all.dart';
import '../skins/skin.dart';
import 'instruments_screen.dart';
import 'share.dart';

const _retentionChoices = [7, 30, 90, 365];
const _capChoicesMb = [10, 50, 200, 1000];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.prefs,
    required this.registry,
    required this.store,
    this.share = shareBytes,
  });
  final Prefs prefs;
  final Registry registry;
  final Store store;
  final ShareBytesFn share;

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(
        children: [
          DropdownButtonFormField<String>(
            key: const Key('skin'),
            initialValue: prefs.skinId,
            decoration: const InputDecoration(labelText: 'Skin'),
            items: [
              for (final s in skins)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => prefs.setSkinId(v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('retention'),
            initialValue: prefs.limits.retentionDays,
            decoration: const InputDecoration(labelText: 'Keep readings for'),
            items: [
              for (final d in _retentionChoices)
                DropdownMenuItem(value: d, child: Text('$d days')),
            ],
            onChanged: (v) => prefs.setLimits(
              Limits(retentionDays: v!, capBytes: prefs.limits.capBytes),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('cap'),
            initialValue: prefs.limits.capBytes ~/ (1024 * 1024),
            decoration: const InputDecoration(labelText: 'Storage cap'),
            items: [
              for (final m in _capChoicesMb)
                DropdownMenuItem(value: m, child: Text('$m MB')),
            ],
            onChanged: (v) => prefs.setLimits(
              Limits(
                retentionDays: prefs.limits.retentionDays,
                capBytes: v! * 1024 * 1024,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Material.transparency gives the ListTile its own ink-painting ancestor, so
          // the opaque tileColor below doesn't hide its background/splash (framework assertion otherwise).
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              tileColor: orc.panel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(orc.railRadius),
              ),
              title: Text(
                orc.text('Instruments'),
                style: TextStyle(
                  color: orc.accent,
                  fontFamily: orc.displayFont,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Order, show, logging',
                style: TextStyle(color: orc.accent.withValues(alpha: 0.6)),
              ),
              trailing: Icon(Icons.chevron_right, color: orc.accent),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InstrumentsScreen(
                    registry: registry,
                    store: store,
                    share: share,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
