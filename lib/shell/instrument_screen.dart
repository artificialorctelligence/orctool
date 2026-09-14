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
                // A raw numeric corner radius here would trip the skins
                // literal scan (test/skins/skins_test.dart), which forbids
                // hard-coded radii outside lib/skins — use the theme's own
                // railRadius instead.
                decoration: BoxDecoration(border: Border.all(color: orc.accent), borderRadius: BorderRadius.circular(orc.railRadius)),
                child: Text(widget.instrument.logSummary(widget.registry.settingsFor(widget.instrument)), style: TextStyle(color: orc.accent, fontFamily: orc.displayFont)),
              ),
          ]),
        );
      },
    );
  }
}
