import 'package:flutter/material.dart';

import '../core/instrument.dart';
import '../core/registry.dart';
import '../core/store.dart';
import '../core/workbook.dart';
import '../skins/skin.dart';
import 'share.dart';

/// The registry UI: drag to reorder the rail; show; log on/off; details ›.
class InstrumentsScreen extends StatelessWidget {
  const InstrumentsScreen({
    super.key,
    required this.registry,
    required this.store,
    this.share = shareBytes,
  });
  final Registry registry;
  final Store store;
  final ShareBytesFn share;

  Future<void> _toggleLog(BuildContext context, Instrument i, bool on) async {
    if (on) {
      final why = await i.logPrecondition();
      if (why != null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(why)));
        }
        return;
      }
    }
    await registry.setLogging(i, on);
  }

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final style = TextStyle(
      color: orc.accent,
      fontFamily: orc.displayFont,
      fontWeight: FontWeight.bold,
    );
    return Scaffold(
      backgroundColor: orc.ground,
      appBar: AppBar(
        backgroundColor: orc.accent,
        foregroundColor: orc.onAccent,
        title: Text(orc.text('Instruments')),
      ),
      body: ListenableBuilder(
        listenable: registry,
        builder: (context, _) {
          final items = registry.ordered;
          final legend = TextStyle(
            color: orc.accent.withValues(alpha: 0.7),
            fontFamily: orc.displayFont,
            fontSize: 12,
          );
          return Column(
            children: [
              // Legend for the unlabelled controls on every row, right-aligned over them.
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        orc.text('drag to reorder the rail'),
                        style: legend,
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        orc.text('Show'),
                        style: legend,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        orc.text('Log'),
                        style: legend,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        orc.text('More'),
                        style: legend,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: items.length,
                  onReorderItem: registry.reorder,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    return Container(
                      key: ValueKey(i.id),
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: orc.panel,
                        borderRadius: BorderRadius.circular(orc.railRadius),
                      ),
                      // Material.transparency gives the ListTile its own ink-painting ancestor, so
                      // the opaque decoration above doesn't hide its background/splash (framework assertion otherwise).
                      child: Material(
                        type: MaterialType.transparency,
                        child: ListTile(
                          leading: ReorderableDragStartListener(
                            index: index,
                            child: Icon(Icons.drag_handle, color: orc.accent),
                          ),
                          title: Text(
                            orc.text(i.name),
                            style: style,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: 'Show',
                                child: Switch.adaptive(
                                  key: Key('show-${i.id}'),
                                  value: registry.isShown(i.id),
                                  onChanged: (v) => registry.setShown(i.id, v),
                                ),
                              ),
                              if (i.canLog)
                                Tooltip(
                                  message: 'Log',
                                  child: Switch.adaptive(
                                    key: Key('log-${i.id}'),
                                    value: registry.isLogging(i.id),
                                    onChanged: (v) => _toggleLog(context, i, v),
                                  ),
                                )
                              else
                                const SizedBox(width: 60),
                              IconButton(
                                key: Key('details-${i.id}'),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36),
                                icon: Icon(
                                  Icons.chevron_right,
                                  color: orc.accent,
                                ),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => LogSettingsScreen(
                                      registry: registry,
                                      instrument: i,
                                      store: store,
                                      share: share,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Interval (common) above the instrument's own details form.
class LogSettingsScreen extends StatefulWidget {
  const LogSettingsScreen({
    super.key,
    required this.registry,
    required this.instrument,
    required this.store,
    required this.share,
  });
  final Registry registry;
  final Instrument instrument;
  final Store store;
  final ShareBytesFn share;

  @override
  State<LogSettingsScreen> createState() => _LogSettingsScreenState();
}

class _LogSettingsScreenState extends State<LogSettingsScreen> {
  late LogSettings _s = widget.registry.settingsFor(widget.instrument);
  late Future<List<RunSummary>> _runs = widget.store.runs(
    instrument: widget.instrument.id,
  );

  Future<void> _export(List<RunSummary> runs) async {
    final withRows = [
      for (final r in runs) (r, await widget.store.rows(r.runId)),
    ];
    await widget.share(workbook(withRows), '${widget.instrument.id}.xlsx');
  }

  Future<void> _clear(int rows) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('Clear ${widget.instrument.name} history?'),
        content: Text(
          'Deletes all $rows ${rows == 1 ? 'row' : 'rows'} — every session and log of this instrument. Logging, if on, continues from empty.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.store.deleteInstrument(widget.instrument.id);
    if (!mounted) return;
    setState(() {
      _runs = widget.store.runs(instrument: widget.instrument.id);
    });
  }

  Future<void> _update(LogSettings s) async {
    final before = _s;
    setState(() => _s = s);
    try {
      await widget.registry.setLogSettings(widget.instrument, s);
    } catch (e) {
      // The scheduler or prefs refused: revert the form and say so.
      if (!mounted) return;
      setState(() => _s = before);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final heading = TextStyle(
      color: orc.accent,
      fontFamily: orc.displayFont,
      fontWeight: FontWeight.bold,
    );
    return Scaffold(
      backgroundColor: orc.ground,
      appBar: AppBar(
        backgroundColor: orc.accent,
        foregroundColor: orc.onAccent,
        title: Text(orc.text(widget.instrument.name)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.instrument.canLog) ...[
            Text(orc.text('Logging'), style: heading),
            const SizedBox(height: 8),
            DropdownButtonFormField<LogInterval>(
              key: const Key('interval'),
              initialValue: _s.interval,
              decoration: const InputDecoration(labelText: 'Sample every'),
              items: [
                for (final v in LogInterval.values)
                  DropdownMenuItem(value: v, child: Text(v.label)),
              ],
              onChanged: (v) => _update(_s.copyWith(interval: v)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android may delay a scheduled sample to save battery; the gap shows in Records.',
            ),
            const SizedBox(height: 16),
            widget.instrument.buildLogSettings(context, _s, _update),
            const SizedBox(height: 24),
          ],
          Text(orc.text('Data'), style: heading),
          const SizedBox(height: 8),
          FutureBuilder<List<RunSummary>>(
            future: _runs,
            builder: (context, snap) {
              final runs = snap.data ?? const <RunSummary>[];
              final rows = runs.fold(0, (n, r) => n + r.rows);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${runs.length} ${runs.length == 1 ? 'recording' : 'recordings'}, $rows ${rows == 1 ? 'row' : 'rows'}',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: runs.isEmpty ? null : () => _export(runs),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Export all recordings'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: rows == 0 ? null : () => _clear(rows),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Clear history'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'One spreadsheet, a tab per recording — opens in Excel, LibreOffice or OpenOffice.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
