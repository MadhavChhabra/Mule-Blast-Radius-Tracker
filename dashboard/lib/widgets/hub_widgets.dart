import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// The verdict card (2c): the answer stated in plain English before any number, with risk and the
/// version bump as two stat wells, and the safe way to ship it underneath.
class VerdictCard extends StatelessWidget {
  final AnalyzeResult result;
  final Color riskColor;
  final String versionText;
  const VerdictCard({
    super.key,
    required this.result,
    required this.riskColor,
    required this.versionText,
  });

  /// One sentence a developer can act on without reading the table below it.
  String get _headline {
    final s = result.summary;
    if (s.total == 0) return 'Nothing changed.';
    if (s.breaking == 0) return 'Safe to ship.';
    if (s.impactedConsumers == 0) return 'Breaking, but nothing known depends on it.';
    return result.advisory.recommendedBump == 'MAJOR'
        ? 'Don’t ship this as a minor.'
        : 'This breaks a real consumer.';
  }

  String get _explanation {
    final s = result.summary;
    if (s.total == 0) return 'The two specs are identical.';
    if (s.breaking == 0) {
      return '${s.total} change${s.total == 1 ? "" : "s"}, none of them breaking. '
          'No consumer has to do anything.';
    }
    final c = s.impactedConsumers;
    if (c == 0) {
      return '${s.breaking} breaking change${s.breaking == 1 ? "" : "s"} — no known consumer is '
          'affected, though your coverage may be incomplete.';
    }
    return '${s.breaking} breaking change${s.breaking == 1 ? "" : "s"} affecting '
        '$c consumer${c == 1 ? "" : "s"}.';
  }

  String? get _remediation {
    for (final i in result.impacts) {
      final r = i.change.remediation;
      if (i.change.classification == 'BREAKING' && r != null && r.isNotEmpty) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final breaking = result.summary.breaking > 0;
    final accent = breaking ? AppColors.breaking : AppColors.additive;
    final remediation = _remediation;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.09), accent.withOpacity(0.02)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: accent.withOpacity(0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 560;
          final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('VERDICT',
                style: monoLabel(
                    color: breaking ? AppColors.breakingText : AppColors.additive)),
            const SizedBox(height: 8),
            Text(_headline,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(_explanation,
                style: const TextStyle(fontSize: 13, height: 1.55, color: AppColors.textDim)),
          ]);
          final wells = Row(mainAxisSize: MainAxisSize.min, children: [
            StatWell(
              label: 'RISK',
              value: '${result.advisory.riskScore}',
              caption: '${result.advisory.riskLevel} /100',
              color: riskColor,
            ),
            const SizedBox(width: 10),
            StatWell(
              label: 'VERSION',
              value: result.advisory.nextVersion ?? '—',
              caption: result.advisory.currentVersion == null
                  ? result.advisory.recommendedBump
                  : '${result.advisory.recommendedBump} ← ${result.advisory.currentVersion}',
            ),
          ]);
          return wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: text),
                  const SizedBox(width: 18),
                  wells,
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  text,
                  const SizedBox(height: 14),
                  wells,
                ]);
        }),
        if (remediation != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.additive.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.additive.withOpacity(0.28)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.health_and_safety, size: 17, color: AppColors.additive),
              const SizedBox(width: 11),
              Expanded(
                child: RichText(
                  text: TextSpan(children: [
                    const TextSpan(
                        text: 'Ship it safely  ',
                        style: TextStyle(
                            fontFamily: kSans,
                            fontSize: 12.5,
                            height: 1.6,
                            fontWeight: FontWeight.w600,
                            color: AppColors.additive)),
                    TextSpan(
                        text: remediation,
                        style: const TextStyle(
                            fontFamily: kSans,
                            fontSize: 12.5,
                            height: 1.6,
                            color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A 104px stat well: mono kicker, the figure in Light 300, a mono caption.
class StatWell extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final Color? color;
  const StatWell({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: 104,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: monoData(size: 9.5)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: statStyle(24, color: color)),
          const SizedBox(height: 4),
          Text(caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoData(size: 9.5, color: AppColors.textMuted)),
        ]),
      );
}

/// The lineage strip (2c): orientation in ~200px instead of re-rendering the whole network inside
/// the hub, so nothing competes with the answer column for attention.
class LineageStrip extends StatelessWidget {
  final String apiId;
  final GraphDto graph;
  final void Function(String api)? onOpen;
  final VoidCallback? onBack;
  const LineageStrip({
    super.key,
    required this.apiId,
    required this.graph,
    this.onOpen,
    this.onBack,
  });

  String _layerOf(String id) {
    for (final n in graph.nodes) {
      if (n.id == id) return n.layer;
    }
    return 'UNKNOWN';
  }

  @override
  Widget build(BuildContext context) {
    final callers = graph.edges.where((e) => e.to == apiId).toList();
    final calls = graph.edges.where((e) => e.from == apiId).toList();
    final layer = _layerOf(apiId);
    final layerColor = AppColors.forLayer(layer);

    Widget row(String id, String edgeLayer, String risk) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: InkWell(
            onTap: onOpen == null ? null : () => onOpen!(id),
            borderRadius: BorderRadius.circular(AppRadius.field),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.fillSubtle,
                borderRadius: BorderRadius.circular(AppRadius.field),
                border: Border(
                    left: BorderSide(color: AppColors.forLayer(edgeLayer), width: 2)),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                ),
                if (risk != 'none')
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: risk == 'breaking' ? AppColors.breaking : AppColors.warning,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ]),
            ),
          ),
        );

    return Container(
      width: 212,
      color: AppColors.bar,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (onBack != null)
          InkWell(
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Row(children: [
                Icon(Icons.arrow_back, size: 16, color: AppColors.textMuted),
                SizedBox(width: 7),
                // Flexible so a wider face or a longer translation ellipses instead of overflowing
                // the fixed 212px strip.
                Flexible(
                  child: Text('Back to estate',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ),
              ]),
            ),
          ),
        Text('LINEAGE', style: monoLabel()),
        const SizedBox(height: 14),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CALLED BY', style: monoData(size: 10)),
              const SizedBox(height: 7),
              if (callers.isEmpty)
                Text('nothing yet', style: monoData(size: 10.5, color: AppColors.textGhost)),
              for (final e in callers.take(6)) row(e.from, _layerOf(e.from), e.risk),
              const _StripArrow(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                decoration: BoxDecoration(
                  color: layerColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: Border.all(color: layerColor.withOpacity(0.35)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(apiId,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(layer, style: monoData(size: 10, color: layerColor)),
                ]),
              ),
              const _StripArrow(),
              Text('CALLS', style: monoData(size: 10)),
              const SizedBox(height: 7),
              if (calls.isEmpty)
                Text('nothing downstream',
                    style: monoData(size: 10.5, color: AppColors.textGhost)),
              for (final e in calls.take(6)) row(e.to, _layerOf(e.to), e.risk),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        SolidPanel(
          fill: AppColors.fillSubtle,
          padding: const EdgeInsets.all(11),
          radius: 10,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ANSWER DEPTH', style: monoData(size: 10)),
            const SizedBox(height: 7),
            _StripDepthBar(coverage: graph.coverage),
            const SizedBox(height: 7),
            Text(
              graph.coverage.dependencies == 0
                  ? 'nothing mapped yet'
                  : '${graph.coverage.endpointLevel} of ${graph.coverage.dependencies} '
                      'dependencies answerable per field',
              style: const TextStyle(fontSize: 11, height: 1.45, color: AppColors.textMuted),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _StripArrow extends StatelessWidget {
  const _StripArrow();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 24,
        child: Center(child: Icon(Icons.arrow_downward, size: 16, color: AppColors.textGhost)),
      );
}

class _StripDepthBar extends StatelessWidget {
  final GraphCoverage coverage;
  const _StripDepthBar({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final known = coverage.endpointLevel;
    final rest = coverage.shallow;
    if (known + rest == 0) {
      return Container(height: 3, color: Colors.white.withOpacity(0.12));
    }
    return SizedBox(
      height: 3,
      child: Row(children: [
        if (known > 0)
          Expanded(
            flex: known,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: AppColors.additive, borderRadius: BorderRadius.circular(2))),
          ),
        if (known > 0 && rest > 0) const SizedBox(width: 2),
        if (rest > 0)
          Expanded(
            flex: rest,
            child: DecoratedBox(
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(2))),
          ),
      ]),
    );
  }
}
