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
                  // Material.transparency gives the ListTile its own ink-painting ancestor, so
                  // the opaque decoration above doesn't hide its background/splash (framework assertion otherwise).
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      title: Text(orc.text(_name(r.instrument)), style: chipStyle.copyWith(fontWeight: FontWeight.bold)),
                      subtitle: Text('${r.kind == 'log' ? 'Log' : 'Session'} · ${_when(context, r)}', style: chipStyle.copyWith(color: orc.accent.withValues(alpha: 0.6))),
                      trailing: Text('${r.rows} rows', style: chipStyle),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RunScreen(store: widget.store, run: r, title: _name(r.instrument), share: widget.share))),
                    ),
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
