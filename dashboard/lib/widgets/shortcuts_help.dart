import 'package:flutter/material.dart';

Future<void> showShortcutsHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ShortcutsHelpDialog(),
  );
}

class _ShortcutsHelpDialog extends StatelessWidget {
  const _ShortcutsHelpDialog();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.keyboard_alt_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Keyboard shortcuts',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
              const SizedBox(height: 8),
              _group(context, 'Anywhere', const [
                _Row(['Ctrl', 'K'], 'Open the search palette'),
                _Row(['⌘', 'K'], 'Open the search palette (macOS)'),
                _Row(['Ctrl', '/'], 'Open this help dialog'),
                _Row(['Esc'], 'Close dialog / palette'),
              ]),
              _group(context, 'In the search palette', const [
                _Row(['↑'], 'Move focus up'),
                _Row(['↓'], 'Move focus down'),
                _Row(['Enter'], 'Open the focused result'),
              ]),
              _group(context, 'In the estate map', const [
                _Row(['+'], 'Zoom in (use the toolbar)'),
                _Row(['-'], 'Zoom out (use the toolbar)'),
              ]),
              const SizedBox(height: 8),
              Text('Every icon in the app also carries a tooltip — hover to see it.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<_Row> rows) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          ...rows,
        ]),
      );
}

class _Row extends StatelessWidget {
  final List<String> keys;
  final String description;
  const _Row(this.keys, this.description);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keyStyle = TextStyle(
        fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700,
        color: scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        for (int i = 0; i < keys.length; i++) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(keys[i], style: keyStyle),
          ),
          if (i < keys.length - 1) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('+', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(width: 12),
        Expanded(child: Text(description, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
