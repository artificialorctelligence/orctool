import 'package:flutter/material.dart';

import '../skins/skin.dart';

/// Label/value pairs, two per row — shared shape for every detail band.
class DetailGrid extends StatelessWidget {
  const DetailGrid(this.items, {super.key});
  final Map<String, String> items;
  @override
  Widget build(BuildContext context) {
    final orc = OrcTheme.of(context);
    final style = Theme.of(context).textTheme.bodyMedium!.copyWith(color: orc.accent, fontFamily: orc.displayFont);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final e in items.entries)
          Text.rich(TextSpan(children: [
            TextSpan(text: '${orc.text(e.key)}  ', style: style.copyWith(color: style.color!.withValues(alpha: 0.6))),
            TextSpan(text: e.value, style: style),
          ])),
      ],
    );
  }
}
