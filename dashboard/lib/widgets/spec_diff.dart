import 'package:flutter/material.dart';

import '../theme.dart';

enum DiffOp { context, add, remove }

class DiffLine {
  final DiffOp op;
  final String text;
  final int? oldNo;
  final int? newNo;
  const DiffLine(this.op, this.text, this.oldNo, this.newNo);
}

/// Line-level diff via longest-common-subsequence. Pure, testable, no deps.
List<DiffLine> computeLineDiff(String oldText, String newText) {
  final a = _splitLines(oldText);
  final b = _splitLines(newText);
  final m = a.length, n = b.length;

  // LCS length table.
  final lcs = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (int i = m - 1; i >= 0; i--) {
    for (int j = n - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final out = <DiffLine>[];
  int i = 0, j = 0, oldNo = 1, newNo = 1;
  while (i < m && j < n) {
    if (a[i] == b[j]) {
      out.add(DiffLine(DiffOp.context, a[i], oldNo++, newNo++));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add(DiffLine(DiffOp.remove, a[i], oldNo++, null));
      i++;
    } else {
      out.add(DiffLine(DiffOp.add, b[j], null, newNo++));
      j++;
    }
  }
  while (i < m) {
    out.add(DiffLine(DiffOp.remove, a[i++], oldNo++, null));
  }
  while (j < n) {
    out.add(DiffLine(DiffOp.add, b[j++], null, newNo++));
  }
  return out;
}

List<String> _splitLines(String s) {
  if (s.isEmpty) return const [];
  return s.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
}

/// Collapses long runs of unchanged context to keep the diff readable, keeping
/// [pad] context lines around each change.
List<DiffLine> collapseContext(List<DiffLine> lines, {int pad = 3}) {
  final keep = List<bool>.filled(lines.length, false);
  for (int k = 0; k < lines.length; k++) {
    if (lines[k].op != DiffOp.context) {
      for (int d = -pad; d <= pad; d++) {
        final idx = k + d;
        if (idx >= 0 && idx < lines.length) keep[idx] = true;
      }
    }
  }
  final out = <DiffLine>[];
  bool gap = false;
  for (int k = 0; k < lines.length; k++) {
    if (keep[k]) {
      out.add(lines[k]);
      gap = false;
    } else if (!gap) {
      out.add(const DiffLine(DiffOp.context, '⋯', null, null));
      gap = true;
    }
  }
  return out;
}

class SpecDiffView extends StatelessWidget {
  final String oldText;
  final String newText;
  final bool collapse;
  const SpecDiffView({super.key, required this.oldText, required this.newText, this.collapse = true});

  @override
  Widget build(BuildContext context) {
    var lines = computeLineDiff(oldText, newText);
    final added = lines.where((l) => l.op == DiffOp.add).length;
    final removed = lines.where((l) => l.op == DiffOp.remove).length;
    if (collapse) lines = collapseContext(lines);

    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _tag(context, '+$added', AppColors.additive),
        const SizedBox(width: 6),
        _tag(context, '-$removed', AppColors.breaking),
        const SizedBox(width: 10),
        Text('line-level diff', style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 8),
      Container(
        constraints: const BoxConstraints(maxHeight: 360),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: lines.length,
            itemBuilder: (context, k) => _line(context, lines[k]),
          ),
        ),
      ),
    ]);
  }

  Widget _tag(BuildContext context, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11,
                fontFamily: 'monospace')),
      );

  Widget _line(BuildContext context, DiffLine l) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, gutter, sign) = switch (l.op) {
      DiffOp.add => (AppColors.additive.withOpacity(0.12), AppColors.additive, '+'),
      DiffOp.remove => (AppColors.breaking.withOpacity(0.12), AppColors.breaking, '-'),
      DiffOp.context => (Colors.transparent, scheme.onSurfaceVariant, ' '),
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 34,
          child: Text(l.oldNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'monospace', fontSize: 10.5,
                  color: scheme.onSurfaceVariant.withOpacity(0.6))),
        ),
        SizedBox(
          width: 34,
          child: Text(l.newNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(fontFamily: 'monospace', fontSize: 10.5,
                  color: scheme.onSurfaceVariant.withOpacity(0.6))),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 10,
          child: Text(sign,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                  fontWeight: FontWeight.w700, color: gutter)),
        ),
        Expanded(
          child: Text(l.text,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                  color: l.op == DiffOp.context ? scheme.onSurface : gutter)),
        ),
      ]),
    );
  }
}
