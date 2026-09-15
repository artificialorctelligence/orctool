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
            onReorderItem: registry.reorder,
            itemBuilder: (context, index) {
              final i = items[index];
              return Container(
                key: ValueKey(i.id),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: orc.panel, borderRadius: BorderRadius.circular(orc.railRadius)),
                // Material.transparency gives the ListTile its own ink-painting ancestor, so
                // the opaque decoration above doesn't hide its background/splash (framework assertion otherwise).
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle, color: orc.accent)),
                    title: Text(orc.text(i.name), style: style, overflow: TextOverflow.ellipsis),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Tooltip(message: 'Show', child: Switch.adaptive(key: Key('show-${i.id}'), value: registry.isShown(i.id), onChanged: (v) => registry.setShown(i.id, v))),
                      if (i.canLog) ...[
                        Tooltip(message: 'Log', child: Switch.adaptive(key: Key('log-${i.id}'), value: registry.isLogging(i.id), onChanged: (v) => _toggleLog(context, i, v))),
                        IconButton(
                          key: Key('details-${i.id}'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 36),
                          icon: Icon(Icons.chevron_right, color: orc.accent),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LogSettingsScreen(registry: registry, instrument: i))),
                        ),
                      ],
                    ]),
                  ),
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
    final before = _s;
    setState(() => _s = s);
    try {
      await widget.registry.setLogSettings(widget.instrument, s);
    } catch (e) {
      // The scheduler or prefs refused: revert the form and say so.
      if (!mounted) return;
      setState(() => _s = before);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
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
