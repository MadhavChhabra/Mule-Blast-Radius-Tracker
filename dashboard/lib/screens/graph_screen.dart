import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../util/file_upload.dart' as web_util;
import '../widgets.dart';

class GraphScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn? open;
  const GraphScreen({super.key, required this.api, this.open});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  String _search = '';
  String? _selected;
  bool _showStandalone = false;
  bool _showGovernance = true;
  Future<GraphDto>? _future;
  List<InsightFinding> _findings = const [];

  @override
  void initState() {
    super.initState();
    _future = widget.api.graph();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    try {
      final f = await widget.api.insights();
      if (mounted) setState(() => _findings = f);
    } catch (_) {}
  }

  Set<String> _connectedIds(GraphDto graph) {
    final ids = <String>{};
    for (final e in graph.edges) {
      ids.add(e.from);
      ids.add(e.to);
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScreenHeader('API-led estate map',
            'Consumer apps → Experience → Process → System. Red edges carry a breaking change.',
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  final next = widget.api.graph(refresh: true);
                  setState(() {
                    _future = next;
                  });
                  _loadInsights();
                },
                icon: const Icon(Icons.refresh),
              ),
            ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(children: [
            SizedBox(
              width: 320,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                  hintText: 'Search APIs / apps',
                ),
                onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
              ),
            ),
            if (_findings.isNotEmpty) ...[
              const SizedBox(width: 12),
              Tooltip(
                message: 'Paint governance findings on the map:\n'
                    'dashed red = upward call / dependency cycle\n'
                    'dashed amber = layer skip\n'
                    'flame = change hotspot',
                child: FilterChip(
                  avatar: Icon(Icons.policy_outlined, size: 16,
                      color: _showGovernance ? AppColors.breaking : null),
                  label: Text('Governance (${_findings.length})'),
                  selected: _showGovernance,
                  onSelected: (v) => setState(() => _showGovernance = v),
                ),
              ),
            ],
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: 'Export the estate map',
              onSelected: (path) => web_util.openDownload('$apiBase$path'),
              itemBuilder: (_) => const [
                PopupMenuItem(value: '/api/graph/export.svg?download=true',
                    child: Text('Estate map (SVG)')),
                PopupMenuItem(value: '/api/graph/export.csv?kind=nodes&download=true',
                    child: Text('Nodes (CSV)')),
                PopupMenuItem(value: '/api/graph/export.csv?kind=edges&download=true',
                    child: Text('Edges (CSV)')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.file_download_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Export ▾'),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            const _Legend(),
          ]),
        ),
        Expanded(
          child: AsyncView<GraphDto>(
            future: _future!,
            builder: (context, graph) {
              if (graph.nodes.isEmpty) {
                return EmptyState(
                  icon: Icons.hub_outlined,
                  title: 'No estate map yet',
                  message: 'Add a repo or connect Anypoint in Sources, then Sync everything to build the map.',
                  action: widget.open == null
                      ? null
                      : FilledButton.icon(
                          onPressed: () => widget.open!(Tabs.sources),
                          icon: const Icon(Icons.cable_outlined, size: 18),
                          label: const Text('Go to Sources'),
                        ),
                );
              }
              final connectedIds = _connectedIds(graph);
              final standalone = graph.nodes.length - connectedIds.length;
              final overlay = _GovernanceOverlay.build(_findings, graph.edges, _showGovernance);
              return Row(children: [
                Expanded(
                  child: Column(children: [
                    if (standalone > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                        child: Row(children: [
                          Text('$standalone standalone API(s) hidden',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 8),
                          Switch(
                            value: _showStandalone,
                            onChanged: (v) => setState(() => _showStandalone = v),
                          ),
                          Text(_showStandalone ? 'showing all' : 'connected only',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                      ),
                    Expanded(
                      child: _LayeredMap(
                        graph: graph,
                        search: _search,
                        selected: _selected,
                        showStandalone: _showStandalone,
                        connectedIds: connectedIds,
                        overlay: overlay,
                        onSelect: (id) => setState(() => _selected = id),
                      ),
                    ),
                  ]),
                ),
                if (_selected != null)
                  _DetailPanel(
                    node: graph.nodes.firstWhere((n) => n.id == _selected,
                        orElse: () => graph.nodes.first),
                    graph: graph,
                    findings: _findings,
                    open: widget.open,
                    onClose: () => setState(() => _selected = null),
                    onSelect: (id) => setState(() => _selected = id),
                  ),
              ]);
            },
          ),
        ),
      ],
    );
  }
}

const List<String> _layerOrder = ['APP', 'EXPERIENCE', 'PROCESS', 'SYSTEM', 'BACKEND', 'UNKNOWN'];

class _GovernanceOverlay {
  final Map<String, String> edgeSeverity;
  final Set<String> cycleNodes;
  final Set<String> hotspotNodes;
  final bool enabled;
  const _GovernanceOverlay(this.edgeSeverity, this.cycleNodes, this.hotspotNodes, this.enabled);

  factory _GovernanceOverlay.build(List<InsightFinding> findings, List<GraphEdge> edges, bool enabled) {
    final sev = <String, String>{};
    final cyc = <String>{};
    final hot = <String>{};
    final cycleGroups = <Set<String>>[];
    for (final f in findings) {
      switch (f.rule) {
        case 'upward-call':
          if (f.apis.length >= 2) sev['${f.apis[0]}|${f.apis[1]}'] = 'high';
        case 'layer-skip':

          if (f.severity == 'medium' && f.apis.length >= 2) {
            sev.putIfAbsent('${f.apis[0]}|${f.apis[1]}', () => 'medium');
          }
        case 'dependency-cycle':
          cyc.addAll(f.apis);
          cycleGroups.add(f.apis.toSet());
        case 'change-hotspot':
          if (f.apis.isNotEmpty) hot.add(f.apis.first);
      }
    }

    for (final e in edges) {
      for (final g in cycleGroups) {
        if (g.contains(e.from) && g.contains(e.to)) {
          sev['${e.from}|${e.to}'] = 'high';
          break;
        }
      }
    }
    return _GovernanceOverlay(sev, cyc, hot, enabled);
  }

  String? severityFor(String from, String to) => enabled ? edgeSeverity['$from|$to'] : null;
  bool inCycle(String id) => enabled && cycleNodes.contains(id);
  bool isHotspot(String id) => enabled && hotspotNodes.contains(id);
}

void _orderColumnsToReduceCrossings(
    List<String> columns, Map<String, List<GraphNode>> byLayer, List<GraphEdge> edges) {
  final adj = <String, List<String>>{};
  for (final e in edges) {
    adj.putIfAbsent(e.from, () => []).add(e.to);
    adj.putIfAbsent(e.to, () => []).add(e.from);
  }

  for (final l in columns) {
    byLayer[l]!.sort((a, b) => b.dependedOnBy.compareTo(a.dependedOnBy));
  }
  final row = <String, int>{};
  void reindex() {
    for (final l in columns) {
      final list = byLayer[l]!;
      for (int i = 0; i < list.length; i++) {
        row[list[i].id] = i;
      }
    }
  }

  reindex();
  for (int iter = 0; iter < 6; iter++) {
    final sweep = iter.isEven ? columns : columns.reversed.toList();
    for (final l in sweep) {
      final list = byLayer[l]!;
      final bary = <String, double>{};
      for (final n in list) {
        final neigh = adj[n.id];
        if (neigh == null || neigh.isEmpty) {
          bary[n.id] = (row[n.id] ?? 0).toDouble();
          continue;
        }
        double sum = 0;
        int cnt = 0;
        for (final m in neigh) {
          final p = row[m];
          if (p != null) {
            sum += p;
            cnt++;
          }
        }
        bary[n.id] = cnt > 0 ? sum / cnt : (row[n.id] ?? 0).toDouble();
      }
      list.sort((a, b) => bary[a.id]!.compareTo(bary[b.id]!));
      reindex();
    }
  }
}

class _LayeredMap extends StatefulWidget {
  final GraphDto graph;
  final String search;
  final String? selected;
  final bool showStandalone;
  final Set<String> connectedIds;
  final _GovernanceOverlay overlay;
  final void Function(String) onSelect;
  const _LayeredMap({
    required this.graph,
    required this.search,
    required this.selected,
    required this.showStandalone,
    required this.connectedIds,
    required this.overlay,
    required this.onSelect,
  });

  static const double cardW = 200;
  static const double cardH = 62;
  static const double colGap = 130;
  static const double rowGap = 20;
  static const double padLeft = 24;
  static const double padTop = 52;

  @override
  State<_LayeredMap> createState() => _LayeredMapState();
}

class _LayeredMapState extends State<_LayeredMap> {

  final _pos = <String, Offset>{};
  final _columnCounts = <String, int>{};
  List<GraphNode> _visible = [];
  List<String> _columns = [];
  double _totalW = 400;
  double _totalH = 300;
  double _scale = 0.85;

  final _vCtrl = ScrollController();
  final _hCtrl = ScrollController();
  Size _viewport = Size.zero;
  int _cullTick = 0;

  @override
  void initState() {
    super.initState();
    _recompute();
    _vCtrl.addListener(_onScroll);
    _hCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() => _cullTick++);
  }

  @override
  void didUpdateWidget(covariant _LayeredMap old) {
    super.didUpdateWidget(old);

    if (old.graph != widget.graph || old.showStandalone != widget.showStandalone) {
      _recompute();
    }
  }

  @override
  void dispose() {
    _vCtrl.removeListener(_onScroll);
    _hCtrl.removeListener(_onScroll);
    _vCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  Rect _visibleRect() {
    if (_viewport == Size.zero) {
      return Rect.fromLTWH(0, 0, _totalW, _totalH);
    }
    final vx = _hCtrl.hasClients ? _hCtrl.offset : 0.0;
    final vy = _vCtrl.hasClients ? _vCtrl.offset : 0.0;
    final vw = _viewport.width / _scale;
    final vh = _viewport.height / _scale;
    const margin = _LayeredMap.cardW;
    return Rect.fromLTWH(vx / _scale - margin, vy / _scale - margin,
        vw + margin * 2, vh + margin * 2);
  }

  void _recompute() {
    _pos.clear();
    _columnCounts.clear();

    _visible = widget.showStandalone
        ? widget.graph.nodes
        : widget.graph.nodes.where((n) => widget.connectedIds.contains(n.id)).toList();

    final byLayer = {for (final l in _layerOrder) l: _visible.where((n) => n.layer == l).toList()};
    _columns = _layerOrder.where((l) => byLayer[l]!.isNotEmpty).toList();
    _orderColumnsToReduceCrossings(_columns, byLayer, widget.graph.edges);

    for (int c = 0; c < _columns.length; c++) {
      final list = byLayer[_columns[c]]!;
      _columnCounts[_columns[c]] = list.length;
      for (int i = 0; i < list.length; i++) {
        _pos[list[i].id] = Offset(
            _LayeredMap.padLeft + c * (_LayeredMap.cardW + _LayeredMap.colGap),
            _LayeredMap.padTop + i * (_LayeredMap.cardH + _LayeredMap.rowGap));
      }
    }
    final maxRows = _columns.map((l) => byLayer[l]!.length).fold(0, math.max);
    _totalW = _LayeredMap.padLeft * 2 +
        _columns.length * _LayeredMap.cardW +
        math.max(0, _columns.length - 1) * _LayeredMap.colGap;
    _totalH = _LayeredMap.padTop * 2 + maxRows * (_LayeredMap.cardH + _LayeredMap.rowGap);
  }

  bool _nodeBreaking(String id) =>
      widget.graph.edges.any((e) => e.risk == 'breaking' && (e.to == id || e.from == id));

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final search = widget.search;
    bool matches(GraphNode n) => search.isEmpty || n.label.toLowerCase().contains(search);
    final connected = <String>{};
    if (selected != null) {
      connected.add(selected);
      for (final e in widget.graph.edges) {
        if (e.from == selected) connected.add(e.to);
        if (e.to == selected) connected.add(e.from);
      }
    }

    final children = <Widget>[];
    for (int c = 0; c < _columns.length; c++) {
      final color = AppColors.forLayer(_columns[c]);
      children.add(Positioned(
        left: _LayeredMap.padLeft + c * (_LayeredMap.cardW + _LayeredMap.colGap),
        top: 14,
        width: _LayeredMap.cardW,
        child: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text('${AppColors.layerLabel(_columns[c])}s  (${_columnCounts[_columns[c]]})',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
      ));
    }
    final visRect = _visibleRect();
    for (final n in _visible) {
      final p = _pos[n.id];
      if (p == null) continue;
      final cardRect = Rect.fromLTWH(p.dx, p.dy, _LayeredMap.cardW, _LayeredMap.cardH);
      if (!cardRect.overlaps(visRect)) {
        continue;
      }
      final dim = (selected != null && !connected.contains(n.id)) || !matches(n);
      children.add(Positioned(
        left: p.dx,
        top: p.dy,
        width: _LayeredMap.cardW,
        height: _LayeredMap.cardH,
        child: Opacity(
          opacity: dim ? 0.28 : 1,
          child: _NodeCard(
            node: n,
            selected: selected == n.id,
            breaking: _nodeBreaking(n.id),
            inCycle: widget.overlay.inCycle(n.id),
            hotspot: widget.overlay.isHotspot(n.id),
            onTap: () => widget.onSelect(n.id),
          ),
        ),
      ));
    }

    final canvas = SizedBox(
      width: _totalW,
      height: _totalH,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _EdgePainter(
                edges: widget.graph.edges,
                pos: _pos,
                selected: selected,
                overlay: widget.overlay,
                dimColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
        ...children,
      ]),
    );

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Stack(children: [

        LayoutBuilder(builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _viewport) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _viewport = size);
            });
          }
          return Scrollbar(
            controller: _vCtrl,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _vCtrl,
              scrollDirection: Axis.vertical,
              child: Scrollbar(
                controller: _hCtrl,
                thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 1,
                child: SingleChildScrollView(
                  controller: _hCtrl,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(_totalW * _scale, 400),
                    height: math.max(_totalH * _scale, 300),
                    child: Transform.scale(
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: canvas,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        Positioned(right: 16, bottom: 16, child: _ZoomControls(
          scale: _scale,
          onZoom: (d) => setState(() => _scale = (_scale + d).clamp(0.3, 2.0)),
        )),
      ]),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double scale;
  final void Function(double) onZoom;
  const _ZoomControls({required this.scale, required this.onZoom});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      color: Theme.of(context).colorScheme.surface,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => onZoom(-0.1), icon: const Icon(Icons.remove), tooltip: 'Zoom out'),
        Text('${(scale * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(onPressed: () => onZoom(0.1), icon: const Icon(Icons.add), tooltip: 'Zoom in'),
      ]),
    );
  }
}

class _NodeCard extends StatelessWidget {
  final GraphNode node;
  final bool selected;
  final bool breaking;
  final bool inCycle;
  final bool hotspot;
  final VoidCallback onTap;
  const _NodeCard({required this.node, required this.selected, required this.breaking,
      this.inCycle = false, this.hotspot = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forLayer(node.layer);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : color.withOpacity(0.55), width: selected ? 2.4 : 1.2),
            boxShadow: selected ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 12)] : null,
          ),
          child: Row(children: [
            Container(width: 5, height: double.infinity,
                decoration: BoxDecoration(
                    color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(9)))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(node.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Text(AppColors.layerLabel(node.layer),
                      style: TextStyle(fontSize: 10, color: color)),
                ],
              ),
            ),
            if (breaking) const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.breaking),
            ),
            if (inCycle) const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Tooltip(message: 'Part of a dependency cycle',
                  child: Icon(Icons.loop, size: 15, color: AppColors.breaking)),
            ),
            if (hotspot) const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Tooltip(message: 'Change hotspot — many consumers depend on this',
                  child: Icon(Icons.local_fire_department_outlined, size: 15, color: AppColors.warning)),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                _deg(context, Icons.south_east, node.dependsOn),
                _deg(context, Icons.north_east, node.dependedOnBy),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _deg(BuildContext context, IconData icon, int n) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 1),
        Text('$n', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}

class _EdgePainter extends CustomPainter {
  final List<GraphEdge> edges;
  final Map<String, Offset> pos;
  final String? selected;
  final _GovernanceOverlay overlay;
  final Color dimColor;
  _EdgePainter({required this.edges, required this.pos, required this.selected,
      required this.overlay, required this.dimColor});

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final from = pos[e.from];
      final to = pos[e.to];
      if (from == null || to == null) continue;
      final involved = selected == null || e.from == selected || e.to == selected;

      final start = Offset(from.dx + _LayeredMap.cardW, from.dy + _LayeredMap.cardH / 2);
      final end = Offset(to.dx, to.dy + _LayeredMap.cardH / 2);
      final dx = (end.dx - start.dx).abs() * 0.5;

      Path path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + dx, start.dy, end.dx - dx, end.dy, end.dx, end.dy);

      final violation = overlay.severityFor(e.from, e.to);
      Color color;
      double width;
      if (violation != null) {
        color = violation == 'high' ? AppColors.breaking : AppColors.warning;
        width = 2.2;
        path = _dashed(path);
      } else if (e.risk == 'breaking') {
        color = AppColors.breaking;
        width = 2.4;
      } else if (e.risk == 'safe') {
        color = AppColors.additive;
        width = 1.4;
      } else {
        color = dimColor;
        width = 1.2;
      }

      final double opacity;
      if (selected == null) {
        opacity = violation != null ? 0.85 : (e.risk == 'breaking' ? 0.7 : 0.28);
      } else {
        opacity = involved ? 0.92 : (violation != null ? 0.25 : 0.06);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = involved && selected != null ? width + 0.6 : width
        ..color = color.withOpacity(opacity);
      canvas.drawPath(path, paint);
      _arrowhead(canvas, end, color.withOpacity(opacity));
    }
  }

  static void _arrowhead(Canvas canvas, Offset tip, Color color) {
    const double len = 7;
    const double half = 4;
    final p = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - len, tip.dy - half)
      ..lineTo(tip.dx - len, tip.dy + half)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  static Path _dashed(Path source) {
    final out = Path();
    for (final metric in source.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final len = math.min(8.0, metric.length - d);
        out.addPath(metric.extractPath(d, d + len), Offset.zero);
        d += 13;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.selected != selected || old.edges != edges || old.overlay != overlay;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget chip(String layer) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10,
                decoration: BoxDecoration(color: AppColors.forLayer(layer), shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(AppColors.layerLabel(layer), style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: ['APP', 'EXPERIENCE', 'PROCESS', 'SYSTEM', 'BACKEND'].map(chip).toList()),
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  final GraphNode node;
  final GraphDto graph;
  final List<InsightFinding> findings;
  final OpenFn? open;
  final VoidCallback onClose;
  final void Function(String) onSelect;
  const _DetailPanel({required this.node, required this.graph, this.findings = const [],
      this.open, required this.onClose, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forLayer(node.layer);
    final downstream = graph.edges.where((e) => e.from == node.id).toList();
    final consumers = graph.edges.where((e) => e.to == node.id).toList();
    final nodeFindings = findings.where((f) => f.apis.contains(node.id)).toList();

    return Container(
      width: 320,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(
            child: Text(node.label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          ),
          IconButton(tooltip: 'Close details', onPressed: onClose, icon: const Icon(Icons.close)),
        ]),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(8)),
          child: Text(AppColors.layerLabel(node.layer),
              style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          _stat(context, 'Depends on', node.dependsOn),
          const SizedBox(width: 10),
          _stat(context, 'Consumed by', node.dependedOnBy),
        ]),
        if (open != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: () => open!(Tabs.apiHub, api: node.id),
              icon: const Icon(Icons.open_in_full, size: 16),
              label: const Text('Open in API hub'),
            ),
          ),
        ],
        if (nodeFindings.isNotEmpty) ...[
          const Divider(height: 24),
          _section(context, 'Governance findings'),
          ...nodeFindings.map((f) {
            final c = f.severity == 'high'
                ? AppColors.breaking
                : (f.severity == 'medium' ? AppColors.warning : AppColors.neutral);
            return Tooltip(
              message: f.detail,
              waitDuration: const Duration(milliseconds: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f.title, style: const TextStyle(fontSize: 12))),
                ]),
              ),
            );
          }),
        ],
        if (node.ownerTeam != null || node.reviewers.isNotEmpty) ...[
          const Divider(height: 24),
          if (node.ownerTeam != null) _kv(context, 'Owner team', node.ownerTeam!),
          if (node.reviewers.isNotEmpty)
            _kv(context, 'Reviewers', node.reviewers.map((r) => r.replaceAll('gh:', '')).join(', ')),
        ],
        if (downstream.isNotEmpty) ...[
          const Divider(height: 24),
          _section(context, 'Depends on (downstream)'),
          ...downstream.map((e) => _edgeTile(context, e.to, e.risk, e.via)),
        ],
        if (consumers.isNotEmpty) ...[
          const SizedBox(height: 12),
          _section(context, 'Consumed by (blast radius)'),
          ...consumers.map((e) => _edgeTile(context, e.from, e.risk, e.via)),
        ],
        if (downstream.isEmpty && consumers.isEmpty) ...[
          const Divider(height: 24),
          Text('Independent — no recorded dependencies yet.',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }

  Widget _stat(BuildContext context, String label, int value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _section(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      );

  Widget _edgeTile(BuildContext context, String name, String risk, List<String> via) => InkWell(
        onTap: () => onSelect(name),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: AppColors.forRisk(risk), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                if (risk == 'breaking')
                  const Text('breaking', style: TextStyle(fontSize: 11, color: AppColors.breaking)),
                const Icon(Icons.chevron_right, size: 16),
              ]),

              ...via.map((v) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 2),
                    child: Text(v, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  )),
            ],
          ),
        ),
      );
}
