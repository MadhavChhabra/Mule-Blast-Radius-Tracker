import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../util/file_upload.dart' as web_util;
import '../widgets/global_search.dart';

class HomeScreen extends StatelessWidget {
  final ApiClient api;
  final OpenFn open;
  const HomeScreen({super.key, required this.api, required this.open});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 34, color: scheme.primary),
            const SizedBox(width: 12),
            Text('Wakegraph',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => showGlobalSearch(context, api).then((id) {
                if (id != null) open(Tabs.endpoint, api: id);
              }),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Search'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('See the blast radius of an API change before you merge — no property-file hunting.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        _EstateHealth(api: api, open: open),
        const SizedBox(height: 16),
        _EstateInsights(api: api, open: open),
        const SizedBox(height: 24),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 900;
          final cards = [
            _ActionCard(
              icon: Icons.cable_outlined,
              color: AppColors.additive,
              title: 'Connect your estate',
              body: 'Add your Anypoint org and your Bitbucket/GitHub repos in one place, then Sync '
                  'everything. Relationships are read from contracts, flows and property files.',
              cta: 'Sources',
              onTap: () => open(Tabs.sources),
            ),
            _ActionCard(
              icon: Icons.hub_outlined,
              color: AppColors.seed,
              title: 'See the whole map',
              body: 'The API-led estate — apps → experience → process → system → systems of record. '
                  'Click any node to open it.',
              cta: 'Estate map',
              onTap: () => open(Tabs.graph),
            ),
            _ActionCard(
              icon: Icons.api_outlined,
              color: AppColors.experience,
              title: 'Dive into an API',
              body: 'Everything about one API: its endpoints (what each calls and who calls it), change '
                  'impact, consumers & blast radius, and history — all in one place.',
              cta: 'API hub',
              onTap: () => open(Tabs.apiHub),
            ),
          ];
          return wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < cards.length; i++) ...[
                        Expanded(child: cards[i]),
                        if (i < cards.length - 1) const SizedBox(width: 16),
                      ]
                    ],
                  ),
                )
              : Column(children: [
                  for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: card),
                ]);
        }),
        const SizedBox(height: 24),
        _QuickStart(open: open),
      ],
    );
  }
}

class _EstateHealth extends StatelessWidget {
  final ApiClient api;
  final OpenFn open;
  const _EstateHealth({required this.api, required this.open});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GraphDto>(
      future: api.graph(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _HealthShell(child: Center(child: Padding(
            padding: EdgeInsets.all(24), child: CircularProgressIndicator())));
        }
        if (snap.hasError) {
          return _HealthShell(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.cloud_off, color: AppColors.breaking, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'Server not reachable${apiBase.isEmpty ? '' : ' at $apiBase'}. '
                  'Start it:  ./gradlew :server:bootRun --args=\'--spring.profiles.active=dev\'',
                  style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ));
        }
        final g = snap.data!;
        if (g.nodes.isEmpty) {
          return _HealthShell(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your estate is empty', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Scan a Mule repo or connect Anypoint to build the map.'),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(onPressed: () => open(Tabs.discover),
                    icon: const Icon(Icons.travel_explore, size: 18), label: const Text('Discover')),
              ]),
            ]),
          ));
        }

        int layer(String l) => g.nodes.where((n) => n.layer == l).length;
        final breaking = g.edges.where((e) => e.risk == 'breaking').length;
        final top = (g.nodes.where((n) => n.api).toList()
              ..sort((a, b) => b.dependedOnBy.compareTo(a.dependedOnBy)))
            .take(5)
            .toList();

        return _HealthShell(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Estate health', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => web_util.openDownload('$apiBase/api/report?download=true'),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Report'),
              ),
              TextButton.icon(onPressed: () => open(Tabs.graph),
                  icon: const Icon(Icons.hub_outlined, size: 16), label: const Text('Open map')),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _tile('${g.nodes.length}', 'nodes', AppColors.neutral),
              _tile('${layer('EXPERIENCE')}', 'experience', AppColors.experience),
              _tile('${layer('PROCESS')}', 'process', AppColors.process),
              _tile('${layer('SYSTEM')}', 'system', AppColors.system),
              _tile('${layer('BACKEND')}', 'systems of record', AppColors.backend),
              _tile('${layer('APP')}', 'apps', AppColors.app),
              _tile('$breaking', 'breaking edges', breaking > 0 ? AppColors.breaking : AppColors.additive),
            ]),
            if (top.isNotEmpty) ...[
              const Divider(height: 28),
              Text('Most depended-on APIs', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              ...top.map((n) => _TopRow(node: n, onTap: () => open(Tabs.endpoint, api: n.id))),
            ],
          ]),
        ));
      },
    );
  }

  Widget _tile(String value, String label, Color color) => Builder(
        builder: (context) => Container(
          width: 134,
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          decoration: BoxDecoration(
            color: color.withOpacity(0.09),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 26, height: 1.0, fontWeight: FontWeight.w900,
                    letterSpacing: -0.5, color: color)),
            const SizedBox(height: 5),
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
}

class _EstateInsights extends StatelessWidget {
  final ApiClient api;
  final OpenFn open;
  const _EstateInsights({required this.api, required this.open});

  static const int _maxShown = 6;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([api.insights(), api.graph()]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done || snap.hasError) {
          return const SizedBox.shrink();
        }
        final findings = snap.data![0] as List<InsightFinding>;
        final graph = snap.data![1] as GraphDto;
        if (graph.nodes.isEmpty) return const SizedBox.shrink();
        if (findings.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                const Icon(Icons.verified_outlined, color: AppColors.additive, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('No governance findings — the estate follows API-led direction, '
                      'has no dependency cycles and no change hotspots.',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              ]),
            ),
          );
        }
        final shown = findings.take(_maxShown).toList();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.policy_outlined, size: 20),
                const SizedBox(width: 8),
                Text('Estate insights', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                _countChip(findings),
                const Spacer(),
                if (findings.length > shown.length)
                  Text('+${findings.length - shown.length} more',
                      style: Theme.of(context).textTheme.bodySmall),
              ]),
              const SizedBox(height: 8),
              ...shown.map((f) => _FindingRow(finding: f, open: open)),
            ]),
          ),
        );
      },
    );
  }

  Widget _countChip(List<InsightFinding> findings) {
    final high = findings.where((f) => f.severity == 'high').length;
    final color = high > 0 ? AppColors.breaking : AppColors.warning;
    final label = high > 0 ? '$high high' : '${findings.length} finding(s)';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final InsightFinding finding;
  final OpenFn open;
  const _FindingRow({required this.finding, required this.open});

  Color get _color => switch (finding.severity) {
        'high' => AppColors.breaking,
        'medium' => AppColors.warning,
        _ => AppColors.neutral,
      };

  IconData get _icon => switch (finding.rule) {
        'upward-call' => Icons.u_turn_left,
        'layer-skip' => Icons.redo,
        'dependency-cycle' => Icons.loop,
        'change-hotspot' => Icons.local_fire_department_outlined,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: finding.detail,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: finding.apis.isEmpty ? null : () => open(Tabs.endpoint, api: finding.apis.first),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            Icon(_icon, size: 16, color: _color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(finding.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(finding.severity,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _color)),
            ),
            const Icon(Icons.chevron_right, size: 16),
          ]),
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final GraphNode node;
  final VoidCallback onTap;
  const _TopRow({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forLayer(node.layer);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(node.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${node.dependedOnBy} consumers',
              style: Theme.of(context).textTheme.bodySmall),
          const Icon(Icons.chevron_right, size: 18),
        ]),
      ),
    );
  }
}

class _HealthShell extends StatelessWidget {
  final Widget child;
  const _HealthShell({required this.child});
  @override
  Widget build(BuildContext context) => Card(child: child);
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, body, cta;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(body, style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(onPressed: onTap, child: Text(cta)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickStart extends StatelessWidget {
  final OpenFn open;
  const _QuickStart({required this.open});

  @override
  Widget build(BuildContext context) {
    Widget step(String n, String text, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(children: [
              CircleAvatar(radius: 12, child: Text(n, style: const TextStyle(fontSize: 12))),
              const SizedBox(width: 10),
              Expanded(child: Text(text)),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18),
            ]),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick start', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            step('1', 'Sources — connect Anypoint and/or add a repo, then Sync everything.',
                onTap: () => open(Tabs.sources)),
            step('2', 'Estate map — see the whole API-led network; click any node.',
                onTap: () => open(Tabs.graph)),
            step('3', 'API hub — endpoints, change impact, consumers and history for one API.',
                onTap: () => open(Tabs.apiHub)),
          ],
        ),
      ),
    );
  }
}
