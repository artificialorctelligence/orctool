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
            // The key sits on a wrapper, not the Text itself: callers look up
            // the instrument name as a descendant of this key.
            child: KeyedSubtree(
              key: instrumentName == null ? null : const Key('title-instrument'),
              child: Text(orc.text(instrumentName ?? ''), style: style),
            ),
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
