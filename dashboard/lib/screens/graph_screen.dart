import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../main.dart';
import '../pins.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/skeleton.dart';
import 'first_run.dart';

/// The estate canvas — the home surface. The map is not a tab you visit; it is the ground the
/// whole product sits on, with everything else docked over it as glass.
class GraphScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn? open;
  const GraphScreen({super.key, required this.api, this.open});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

/// Which way the blast path is traced from the focused node.
enum FocusDirection { downstream, upstream, both }

class _GraphScreenState extends State<GraphScreen> {
  Future<GraphDto>? _graph;
  Future<List<InsightFinding>>? _insights;

  String? _focused;
  FocusDirection _direction = FocusDirection.downstream;
  bool _governance = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _graph = widget.api.graph();
      _insights = widget.api.insights().catchError((_) => <InsightFinding>[]);
    });
  }

  void _focus(String? id) => setState(() => _focused = id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GraphDto>(
      future: _graph,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _CanvasBackdrop(child: Center(child: SkeletonList(rows: 3)));
        }
        if (snap.hasError) {
          return _CanvasBackdrop(
            child: Center(
              child: ApiErrorState(
                  error: snap.error!,
                  onRetry: () {
                    widget.api.invalidateGraph();
                    _load();
                  }),
            ),
          );
        }
        final graph = snap.data!;
        if (graph.nodes.isEmpty) {
          return _FirstRunCanvas(
            api: widget.api,
            open: widget.open,
            onDone: () {
              widget.api.invalidateGraph();
              _load();
            },
          );
        }
        return _Estate(
          api: widget.api,
          graph: graph,
          insights: _insights!,
          focused: _focused,
          direction: _direction,
          governance: _governance,
          onFocus: _focus,
          onDirection: (d) => setState(() => _direction = d),
          onGovernance: (v) => setState(() => _governance = v),
          open: widget.open,
        );
      },
    );
  }
}

/// The three stacked backdrop layers: layer bands, a 44px survey grid, and a slow violet sweep.
class _CanvasBackdrop extends StatefulWidget {
  final Widget child;
  final bool bands;
  const _CanvasBackdrop({required this.child, this.bands = true});

  @override
  State<_CanvasBackdrop> createState() => _CanvasBackdropState();
}

class _CanvasBackdropState extends State<_CanvasBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat();

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  static const _bandColors = [
    AppColors.app,
    AppColors.experience,
    AppColors.process,
    AppColors.system,
    AppColors.backend,
  ];

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      color: AppColors.canvas,
      child: Stack(children: [
        if (widget.bands)
          Positioned.fill(
            child: Row(
              children: [
                for (final c in _bandColors)
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.withOpacity(0.075), c.withOpacity(0)],
                          stops: const [0, 0.55],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Positioned.fill(
          child: CustomPaint(painter: _GridPainter()),
        ),
        if (!reduce)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _sweep,
              builder: (context, _) {
                final h = MediaQuery.sizeOf(context).height;
                return Transform.translate(
                  offset: Offset(0, -120 + (_sweep.value * (h + 240))),
                  child: Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.accent.withOpacity(0),
                          AppColors.accent.withOpacity(0.05),
                          AppColors.accent.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        Positioned.fill(child: widget.child),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.022)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

/// Fixed column geometry, transcribed from the comp: x-origins 60 / 330 / 630 / 890 with per-layer
/// widths, rows on a 120px pitch starting at y=276.
class _Layout {
  static const layers = ['APP', 'EXPERIENCE', 'PROCESS', 'SYSTEM', 'BACKEND'];
  static const widths = [190.0, 220.0, 220.0, 190.0, 190.0];
  static const gutters = [80.0, 80.0, 40.0, 80.0];
  static const rowTop = 276.0;
  static const rowPitch = 120.0;
  static const headerOffset = 66.0;
  static const nodeAnchor = 24.0;

  static double columnX(int i) {
    double x = 60;
    for (int k = 0; k < i; k++) {
      x += widths[k] + gutters[k];
    }
    return x;
  }

  static double totalWidth() => columnX(layers.length - 1) + widths.last + 60;
}

class _Placed {
  final GraphNode node;
  final double x;
  final double y;
  final double width;
  const _Placed(this.node, this.x, this.y, this.width);

  Offset get leftAnchor => Offset(x, y + _Layout.nodeAnchor);
  Offset get rightAnchor => Offset(x + width, y + _Layout.nodeAnchor);
}

class _Estate extends StatefulWidget {
  final ApiClient api;
  final GraphDto graph;
  final Future<List<InsightFinding>> insights;
  final String? focused;
  final FocusDirection direction;
  final bool governance;
  final ValueChanged<String?> onFocus;
  final ValueChanged<FocusDirection> onDirection;
  final ValueChanged<bool> onGovernance;
  final OpenFn? open;

  const _Estate({
    required this.api,
    required this.graph,
    required this.insights,
    required this.focused,
    required this.direction,
    required this.governance,
    required this.onFocus,
    required this.onDirection,
    required this.onGovernance,
    required this.open,
  });

  @override
  State<_Estate> createState() => _EstateState();
}

class _EstateState extends State<_Estate> with TickerProviderStateMixin {
  final _h = ScrollController();
  final _v = ScrollController();
  double _scale = 0.85;

  /// Drives the marching dashes on breaking edges.
  late final AnimationController _dash =
      AnimationController(vsync: this, duration: AppMotion.edgeFlow)..repeat();

  /// Drives the staggered path reveal in focus mode.
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1550));

  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  final _positions = <String, _Placed>{};

  @override
  void initState() {
    super.initState();
    _place();
    if (widget.focused != null) _reveal.forward();
  }

  @override
  void didUpdateWidget(covariant _Estate old) {
    super.didUpdateWidget(old);
    if (old.graph != widget.graph) _place();
    if (old.focused != widget.focused) {
      if (widget.focused == null) {
        _reveal.reset();
      } else {
        _reveal.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _dash.dispose();
    _reveal.dispose();
    _breathe.dispose();
    _h.dispose();
    _v.dispose();
    super.dispose();
  }

  void _place() {
    _positions.clear();
    for (int i = 0; i < _Layout.layers.length; i++) {
      final layer = _Layout.layers[i];
      final inLayer = widget.graph.nodes.where((n) => n.layer == layer).toList()
        ..sort((a, b) => b.dependedOnBy.compareTo(a.dependedOnBy));
      for (int r = 0; r < inLayer.length; r++) {
        _positions[inLayer[r].id] = _Placed(
          inLayer[r],
          _Layout.columnX(i),
          _Layout.rowTop + r * _Layout.rowPitch,
          _Layout.widths[i],
        );
      }
    }
    // Anything with an unrecognised layer still needs somewhere to live.
    final unplaced = widget.graph.nodes.where((n) => !_positions.containsKey(n.id)).toList();
    for (int r = 0; r < unplaced.length; r++) {
      _positions[unplaced[r].id] = _Placed(
        unplaced[r],
        _Layout.columnX(_Layout.layers.length - 1),
        _Layout.rowTop + r * _Layout.rowPitch,
        _Layout.widths.last,
      );
    }
  }

  /// Edges on the blast path, in hop order, so the reveal can stagger by distance.
  List<GraphEdge> _pathEdges() {
    final root = widget.focused;
    if (root == null) return const [];
    final out = <GraphEdge>[];
    final seen = <String>{root};
    var frontier = <String>{root};
    while (frontier.isNotEmpty) {
      final next = <String>{};
      for (final e in widget.graph.edges) {
        final down = widget.direction != FocusDirection.upstream;
        final up = widget.direction != FocusDirection.downstream;
        if (down && frontier.contains(e.to) && seen.add(e.from)) {
          out.add(e);
          next.add(e.from);
        }
        if (up && frontier.contains(e.from) && seen.add(e.to)) {
          out.add(e);
          next.add(e.to);
        }
      }
      frontier = next;
    }
    return out;
  }

  Set<String> _pathNodes(List<GraphEdge> edges) {
    final s = <String>{if (widget.focused != null) widget.focused!};
    for (final e in edges) {
      s.add(e.from);
      s.add(e.to);
    }
    return s;
  }

  void _zoom(double delta) =>
      setState(() => _scale = (_scale + delta).clamp(0.3, 2.0));

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final focusing = widget.focused != null;
    final pathEdges = _pathEdges();
    final onPath = _pathNodes(pathEdges);

    // Publish focus upward so the shell's bar can take it over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusState.instance;
      focus.onClose = () => widget.onFocus(null);
      focus.onOpenHub = () => widget.open?.call(Tabs.apiHub, api: widget.focused);
      focus.onDirection = (i) => widget.onDirection(FocusDirection.values[i]);
      focus.set(widget.focused,
          hops: pathEdges.length,
          nodes: onPath.length,
          direction: widget.direction.index);
    });

    final canvasW = _Layout.totalWidth();
    final rows = _Layout.layers
        .map((l) => widget.graph.nodes.where((n) => n.layer == l).length)
        .fold<int>(0, math.max);
    final canvasH = _Layout.rowTop + math.max(rows, 3) * _Layout.rowPitch + 160;

    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape && focusing) {
          widget.onFocus(null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _CanvasBackdrop(
        bands: !focusing,
        child: Stack(children: [
          // ---- the map itself, pannable ----
          Positioned.fill(
            child: Scrollbar(
              controller: _v,
              child: SingleChildScrollView(
                controller: _v,
                child: SingleChildScrollView(
                  controller: _h,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: canvasW * _scale,
                    height: canvasH * _scale,
                    child: Transform.scale(
                      scale: _scale,
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: canvasW,
                        height: canvasH,
                        child: Stack(children: [
                          if (focusing)
                            Positioned(
                              left: (_positions[widget.focused]?.x ?? 0) - 450 + 110,
                              top: (_positions[widget.focused]?.y ?? 0) - 450 + 24,
                              width: 900,
                              height: 900,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [Color(0x1AFF5C61), Color(0x00FF5C61)],
                                    stops: [0, 0.62],
                                  ),
                                ),
                              ),
                            ),
                          Positioned.fill(
                            child: AnimatedBuilder(
                              animation: Listenable.merge([_dash, _reveal]),
                              builder: (context, _) => CustomPaint(
                                painter: _EdgePainter(
                                  edges: widget.graph.edges,
                                  positions: _positions,
                                  pathEdges: pathEdges,
                                  focusing: focusing,
                                  dash: _dash.value,
                                  reveal: reduce ? 1.0 : _reveal.value,
                                  reduce: reduce,
                                ),
                              ),
                            ),
                          ),
                          for (int i = 0; i < _Layout.layers.length; i++)
                            if (widget.graph.nodes.any((n) => n.layer == _Layout.layers[i]))
                              Positioned(
                                left: _Layout.columnX(i),
                                top: _Layout.rowTop - _Layout.headerOffset,
                                child: Text(
                                  '${AppColors.layerBand(_Layout.layers[i])} · '
                                  '${widget.graph.nodes.where((n) => n.layer == _Layout.layers[i]).length}',
                                  style: monoLabel(
                                    size: 10,
                                    color: AppColors.forLayer(_Layout.layers[i])
                                        .withOpacity(focusing ? 0.5 : 1),
                                  ),
                                ),
                              ),
                          // The node layer has to listen to the reveal too — without this the
                          // cards compute their opacity once at value 0 and never repaint, so
                          // focus mode showed edges over an empty canvas.
                          if (focusing)
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: _reveal,
                                builder: (context, _) => Stack(children: [
                                  for (final placed in _positions.values)
                                    _positionedNode(placed, focusing, onPath, pathEdges, reduce),
                                ]),
                              ),
                            )
                          else
                            for (final placed in _positions.values)
                              _positionedNode(placed, focusing, onPath, pathEdges, reduce),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ---- docked chrome ----
          if (!focusing) ...[
            Positioned(left: 28, bottom: 30, child: _SummaryPanel(graph: widget.graph)),
            Positioned(
              right: 28,
              top: 96,
              width: 300,
              child: _AttentionStack(
                insights: widget.insights,
                graph: widget.graph,
                governance: widget.governance,
                onOpen: (api) => widget.onFocus(api),
              ),
            ),
          ],
          if (focusing)
            Positioned(
              right: 28,
              bottom: 30,
              width: 340,
              child: _WhoToTell(
                api: widget.api,
                apiId: widget.focused!,
                graph: widget.graph,
              ),
            ),
          // The comp's focus screen has no zoom cluster — the "who to tell" panel owns that corner.
          if (!focusing)
            Positioned(
              right: 28,
              bottom: 30,
              child: _ZoomCluster(
                scale: _scale,
                onZoom: _zoom,
                onFit: () => setState(() => _scale = 0.85),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Center(
              child: _CommandBar(
                governance: widget.governance,
                focusing: focusing,
                onGovernance: widget.onGovernance,
                onExitFocus: () => widget.onFocus(null),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _positionedNode(_Placed placed, bool focusing, Set<String> onPath,
      List<GraphEdge> pathEdges, bool reduce) {
    final isFocus = placed.node.id == widget.focused;
    final lit = !focusing || onPath.contains(placed.node.id);
    // Each node arrives 400ms after its incoming edge starts drawing.
    final hop = _hopOf(placed.node.id, pathEdges);
    final start = (0.10 + hop * 0.25) / 1.55;
    final popped = reduce || !focusing || _reveal.value >= start;

    return Positioned(
      left: placed.x,
      top: placed.y,
      width: placed.width,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: lit ? (popped ? 1 : 0) : 0.28,
        child: _NodeCard(
          node: placed.node,
          focused: isFocus,
          dimmed: focusing && !lit,
          breaking: widget.graph.edges
              .any((e) => e.risk == 'breaking' && (e.to == placed.node.id || e.from == placed.node.id)),
          shallowOnly: () {
            final touching = widget.graph.edges
                .where((e) => e.to == placed.node.id || e.from == placed.node.id);
            return touching.isNotEmpty && touching.every((e) => !e.endpointLevel);
          }(),
          breathe: isFocus ? _breathe : null,
          onTap: () => widget.onFocus(isFocus ? null : placed.node.id),
          onOpen: () => widget.open?.call(Tabs.apiHub, api: placed.node.id),
        ),
      ),
    );
  }

  int _hopOf(String id, List<GraphEdge> pathEdges) {
    if (id == widget.focused) return 0;
    for (int i = 0; i < pathEdges.length; i++) {
      if (pathEdges[i].from == id || pathEdges[i].to == id) return i + 1;
    }
    return 0;
  }
}

/// Cubic béziers between column gutters, stroked by risk. Breaking edges march; the focus reveal
/// draws each on-path edge from nothing over 500ms, staggered 250ms in hop order.
class _EdgePainter extends CustomPainter {
  final List<GraphEdge> edges;
  final Map<String, _Placed> positions;
  final List<GraphEdge> pathEdges;
  final bool focusing;
  final double dash;
  final double reveal;
  final bool reduce;

  _EdgePainter({
    required this.edges,
    required this.positions,
    required this.pathEdges,
    required this.focusing,
    required this.dash,
    required this.reveal,
    required this.reduce,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final from = positions[e.from];
      final to = positions[e.to];
      if (from == null || to == null) continue;

      // Consumer -> provider reads left to right, so the source is the consumer's right edge.
      final a = from.rightAnchor;
      final b = to.leftAnchor;
      final dx = (b.dx - a.dx).abs() / 2;
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);

      final onPath = pathEdges.contains(e);
      if (focusing && !onPath) {
        canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = Colors.white.withOpacity(0.05));
        continue;
      }

      if (focusing && onPath) {
        final i = pathEdges.indexOf(e);
        final start = (0.10 + i * 0.25) / 1.55;
        final end = start + (0.5 / 1.55);
        final t = reduce ? 1.0 : ((reveal - start) / (end - start)).clamp(0.0, 1.0);
        if (t <= 0) continue;
        final drawn = _partial(path, t);
        final breaking = e.risk == 'breaking';
        canvas.drawPath(
            drawn,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = breaking ? 2 : 1.6
              ..color = breaking ? AppColors.breaking : AppColors.warning);
        continue;
      }

      switch (e.risk) {
        case 'breaking':
          _dashed(canvas, path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6
                ..color = AppColors.breaking);
          break;
        case 'safe':
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..color = AppColors.additive.withOpacity(0.45));
          break;
        default:
          canvas.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.1
                ..color = Colors.white.withOpacity(0.12));
      }
    }
  }

  /// 7-on / 9-off marching dashes. The brief travels dashoffset to -320 over the 6s cycle — a
  /// single 16px period per cycle reads as static, which is what it looked like before.
  void _dashed(Canvas canvas, Path path, Paint paint) {
    const on = 7.0, off = 9.0;
    final phase = reduce ? 0.0 : -320.0 * dash;
    for (final metric in path.computeMetrics()) {
      double d = phase % (on + off);
      if (d > 0) d -= (on + off);
      while (d < metric.length) {
        final s = math.max(d, 0.0);
        final e = math.min(d + on, metric.length);
        if (e > s) canvas.drawPath(metric.extractPath(s, e), paint);
        d += on + off;
      }
    }
  }

  Path _partial(Path path, double t) {
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _EdgePainter old) =>
      old.dash != dash || old.reveal != reveal || old.focusing != focusing;
}

class _NodeCard extends StatefulWidget {
  final GraphNode node;
  final bool focused;
  final bool dimmed;
  final bool breaking;

  /// Every edge touching this node is app-to-app only — no endpoint or field detail.
  final bool shallowOnly;
  final AnimationController? breathe;
  final VoidCallback onTap;
  final VoidCallback onOpen;

  const _NodeCard({
    required this.node,
    required this.focused,
    required this.dimmed,
    required this.breaking,
    required this.shallowOnly,
    required this.breathe,
    required this.onTap,
    required this.onOpen,
  });

  @override
  State<_NodeCard> createState() => _NodeCardState();
}

class _NodeCardState extends State<_NodeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final layer = AppColors.forLayer(widget.node.layer);
    final borderColor = widget.focused
        ? AppColors.breaking
        : widget.dimmed
            ? Colors.white.withOpacity(0.05)
            : (widget.breaking
                ? AppColors.breaking.withOpacity(0.45)
                : (_hover ? layer.withOpacity(0.6) : layer.withOpacity(0.35)));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onOpen,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.dimmed
                ? AppColors.nodeOffPath
                : (widget.focused ? const Color(0xFF171A23) : AppColors.nodeQuiet),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: borderColor, width: widget.focused ? 1.5 : 1),
            boxShadow: widget.focused
                ? [BoxShadow(color: AppColors.breaking.withOpacity(0.35), blurRadius: 60)]
                : (widget.breaking
                    ? [BoxShadow(color: AppColors.breaking.withOpacity(0.22), blurRadius: 40)]
                    : null),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              LayerDot(widget.node.layer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.node.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.focused ? FontWeight.w600 : FontWeight.w500,
                      color: widget.dimmed ? AppColors.textSecondary : AppColors.text,
                    )),
              ),
              if (widget.focused && widget.breathe != null)
                _BreathingDot(controller: widget.breathe!)
              else if (widget.breaking)
                const Icon(Icons.warning_amber_rounded, size: 15, color: AppColors.breaking),
              if (Pins.instance.isPinned(widget.node.id))
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.push_pin, size: 12, color: AppColors.accentSoft),
                ),
            ]),
            if (!widget.dimmed) ...[
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    widget.node.dependedOnBy > 0
                        ? '${widget.node.dependedOnBy} consumer${widget.node.dependedOnBy == 1 ? "" : "s"}'
                        : '${widget.node.dependsOn} dependenc${widget.node.dependsOn == 1 ? "y" : "ies"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoData(size: 10.5),
                  ),
                ),
                // Nothing here is field-level, so any field question about it is a "maybe".
                if (widget.shallowOnly)
                  Text('MAYBE',
                      style: monoData(
                          size: 9.5, color: AppColors.warning, weight: FontWeight.w500)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

class _BreathingDot extends StatelessWidget {
  final AnimationController controller;
  const _BreathingDot({required this.controller});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.breaking,
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: AppColors.breaking.withOpacity(0.35 * (1 - controller.value)),
                blurRadius: 0,
                spreadRadius: 10 * controller.value,
              ),
            ],
          ),
        ),
      );
}

/// Bottom-left: the estate's headline number and how deeply it can be answered.
class _SummaryPanel extends StatelessWidget {
  final GraphDto graph;
  const _SummaryPanel({required this.graph});

  @override
  Widget build(BuildContext context) {
    final breaking = graph.edges.where((e) => e.risk == 'breaking').length;
    final c = graph.coverage;
    final pct = c.dependencies == 0 ? 0 : (c.ratio * 100).round();
    return SizedBox(
      width: 266,
      child: GlassPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('$breaking',
                style: statStyle(38,
                    color: breaking > 0 ? AppColors.breaking : AppColors.additive)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  breaking > 0
                      ? 'breaking edge${breaking == 1 ? "" : "s"}\n'
                          'across ${graph.nodes.length} nodes'
                      : 'breaking edges —\nall ${graph.nodes.length} nodes clear',
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.4, color: AppColors.textDim),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Answer depth',
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            const Spacer(),
            Text('$pct%', style: monoData(size: 12, color: AppColors.text)),
          ]),
          const SizedBox(height: 8),
          _DepthBar(coverage: c, height: 4),
        ]),
      ),
    );
  }
}

/// The stacked answer-depth bar: field-level, endpoint-level, then the unknown remainder.
class _DepthBar extends StatelessWidget {
  final GraphCoverage coverage;
  final double height;
  const _DepthBar({required this.coverage, required this.height});

  @override
  Widget build(BuildContext context) {
    final field = math.max(coverage.fieldLevel, 0);
    final endpoint = math.max(coverage.endpointLevel - coverage.fieldLevel, 0);
    final rest = math.max(coverage.shallow, 0);
    if (field + endpoint + rest == 0) {
      return SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(2)),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: Row(children: [
        if (field > 0)
          Expanded(flex: field, child: _seg(AppColors.additive)),
        if (endpoint > 0) ...[
          if (field > 0) const SizedBox(width: 2),
          Expanded(flex: endpoint, child: _seg(AppColors.experience)),
        ],
        if (rest > 0) ...[
          if (field > 0 || endpoint > 0) const SizedBox(width: 2),
          Expanded(flex: rest, child: _seg(Colors.white.withOpacity(0.12))),
        ],
      ]),
    );
  }

  Widget _seg(Color c) => DecoratedBox(
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
      );
}

/// Right rail: what needs a decision, then what changed since the last visit.
class _AttentionStack extends StatelessWidget {
  final Future<List<InsightFinding>> insights;
  final GraphDto graph;
  final bool governance;
  final ValueChanged<String> onOpen;
  const _AttentionStack({
    required this.insights,
    required this.graph,
    required this.governance,
    required this.onOpen,
  });

  static IconData _icon(String rule) => switch (rule) {
        'upward-call' => Icons.u_turn_left,
        'layer-skip' => Icons.redo,
        'dependency-cycle' => Icons.loop,
        'change-hotspot' => Icons.local_fire_department_outlined,
        _ => Icons.info_outline,
      };

  @override
  Widget build(BuildContext context) {
    final ids = graph.nodes.where((n) => n.api).map((n) => n.id).toList();
    final delta = EstateDelta.since(ids);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (governance)
        FutureBuilder<List<InsightFinding>>(
          future: insights,
          builder: (context, snap) {
            final findings = snap.data ?? const <InsightFinding>[];
            if (findings.isEmpty) return const SizedBox.shrink();
            final high = findings.where((f) => f.severity == 'high').length;
            return GlassPanel(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('NEEDS A DECISION', style: monoLabel()),
                  const Spacer(),
                  if (high > 0) StatusPill('$high HIGH', AppColors.breaking),
                ]),
                const SizedBox(height: 6),
                for (final f in findings.take(3))
                  InkWell(
                    onTap: f.apis.isEmpty ? null : () => onOpen(f.apis.first),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(_icon(f.rule),
                            size: 16,
                            color: f.severity == 'high'
                                ? AppColors.breaking
                                : (f.severity == 'medium'
                                    ? AppColors.warning
                                    : AppColors.textMuted)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(f.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, height: 1.4)),
                        ),
                      ]),
                    ),
                  ),
              ]),
            );
          },
        ),
      if (!delta.isEmpty) ...[
        const SizedBox(height: 10),
        GlassPanel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('SINCE YOU LAST LOOKED', style: monoLabel()),
            const SizedBox(height: 10),
            for (final id in delta.added.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.add, size: 15, color: AppColors.additive),
                  const SizedBox(width: 9),
                  Expanded(
                      child: Text(id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
            for (final id in delta.removed.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.remove, size: 15, color: AppColors.textFaint),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textFaint,
                            decoration: TextDecoration.lineThrough)),
                  ),
                ]),
              ),
          ]),
        ),
      ],
    ]);
  }
}

class _ZoomCluster extends StatelessWidget {
  final double scale;
  final ValueChanged<double> onZoom;
  final VoidCallback onFit;
  const _ZoomCluster({required this.scale, required this.onZoom, required this.onFit});

  @override
  Widget build(BuildContext context) {
    Widget cell(Widget child, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          child: SizedBox(width: 34, height: 32, child: Center(child: child)),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.glassStrong,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.hairlineStrong),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          cell(const Icon(Icons.add, size: 18, color: AppColors.textSecondary),
              () => onZoom(0.1)),
          const Divider(height: 1),
          cell(Text('${(scale * 100).round()}%', style: monoData(size: 10)), onFit),
          const Divider(height: 1),
          cell(const Icon(Icons.remove, size: 18, color: AppColors.textSecondary),
              () => onZoom(-0.1)),
          const Divider(height: 1),
          cell(const Icon(Icons.fit_screen, size: 17, color: AppColors.textSecondary), onFit),
        ]),
      ),
    );
  }
}

/// Bottom-centre: search, then the map's filter words.
class _CommandBar extends StatelessWidget {
  final bool governance;
  final bool focusing;
  final ValueChanged<bool> onGovernance;
  final VoidCallback onExitFocus;
  const _CommandBar({
    required this.governance,
    required this.focusing,
    required this.onGovernance,
    required this.onExitFocus,
  });

  @override
  Widget build(BuildContext context) {
    Widget word(String label, {bool active = false, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Text(label,
                style: monoData(
                    size: 11,
                    color: active ? AppColors.accentSoft : AppColors.textMuted)),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 40, offset: const Offset(0, 12))],
      ),
      child: GlassPanel(
        radius: 14,
        strong: true,
        border: AppColors.hairlineStrong,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search, size: 17, color: AppColors.textFaint),
          const SizedBox(width: 14),
          const SizedBox(
            width: 260,
            child: Text('Search APIs, endpoints, fields…',
                style: TextStyle(fontSize: 13, color: AppColors.textFaint)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.hairlineStrong),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('⌘K', style: monoData(size: 10)),
          ),
          const SizedBox(width: 14),
          Container(width: 1, height: 20, color: AppColors.hairlineStrong),
          const SizedBox(width: 14),
          word('GOVERNANCE', active: governance, onTap: () => onGovernance(!governance)),
          const SizedBox(width: 8),
          word('RISK'),
          const SizedBox(width: 8),
          word('LAYERS'),
          const SizedBox(width: 8),
          word('FOCUS MODE', active: focusing, onTap: focusing ? onExitFocus : null),
        ]),
      ),
    );
  }
}

/// Focus mode replaces the nav bar: what is focused, how far it reaches, and the way out.
/// The top bar in focus mode. Lives here beside the canvas it describes, but is rendered by the
/// shell so it genuinely replaces the nav bar instead of hiding behind it.
class FocusBar extends StatelessWidget {
  final String api;
  final FocusDirection direction;
  final ValueChanged<FocusDirection>? onDirection;
  final int hops;
  final int nodes;
  final VoidCallback onClose;
  final VoidCallback onHub;

  const FocusBar({
    super.key,
    required this.api,
    this.direction = FocusDirection.downstream,
    this.onDirection,
    required this.hops,
    required this.nodes,
    required this.onClose,
    required this.onHub,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(String label, FocusDirection d) => InkWell(
          onTap: onDirection == null ? null : () => onDirection!(d),
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: direction == d ? const Color(0x0FFFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(label,
                style: monoData(
                    size: 11,
                    color: direction == d ? AppColors.text : AppColors.textMuted)),
          ),
        );

    return GlassPanel(
      strong: true,
      border: AppColors.accent.withOpacity(0.28),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: SizedBox(
        height: 50,
        child: Row(children: [
          const Icon(Icons.center_focus_strong, size: 18, color: AppColors.accentSoft),
          const SizedBox(width: 9),
          Flexible(
            child: Text('Focus · $api',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          Container(width: 1, height: 20, color: AppColors.hairlineStrong),
          const SizedBox(width: 16),
          Flexible(
            child: Text('$hops hop${hops == 1 ? "" : "s"} · $nodes nodes on the path',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoData(size: 11.5, color: AppColors.textMuted)),
          ),
          const Spacer(),
          seg('DOWNSTREAM', FocusDirection.downstream),
          seg('UPSTREAM', FocusDirection.upstream),
          seg('BOTH', FocusDirection.both),
          const SizedBox(width: 12),
          FilledButton(onPressed: onHub, child: const Text('Open API hub')),
          const SizedBox(width: 6),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
            tooltip: 'Exit focus  (Esc)',
          ),
        ]),
      ),
    );
  }
}

/// The point of focus mode: the list of people this change obliges you to contact.
class _WhoToTell extends StatelessWidget {
  final ApiClient api;
  final String apiId;
  final GraphDto graph;
  const _WhoToTell({required this.api, required this.apiId, required this.graph});

  @override
  Widget build(BuildContext context) {
    final consumers = graph.edges.where((e) => e.to == apiId).toList();
    return GlassPanel(
      strong: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('WHO YOU HAVE TO TELL', style: monoLabel()),
        const SizedBox(height: 12),
        if (consumers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Nothing depends on this API yet.',
                style: monoData(size: 11, color: AppColors.textMuted)),
          ),
        for (final e in consumers.take(5))
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairlineSoft)),
            ),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: e.risk == 'breaking' ? AppColors.breaking : AppColors.warning,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.from,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                  Text(
                      e.fieldLevel
                          ? 'reads specific fields'
                          : (e.endpointLevel
                              ? 'endpoint-level only'
                              : 'no field data — ask them'),
                      style: monoData(size: 10.5)),
                ]),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              final b = StringBuffer('Heads-up: $apiId is changing\n');
              for (final e in consumers) {
                b.writeln('  [ ] ${e.from} — ${e.fieldLevel ? "reads fields" : "confirm impact"}');
              }
              Clipboard.setData(ClipboardData(text: b.toString()));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Heads-up plan copied')));
            },
            icon: const Icon(Icons.checklist_rtl, size: 16),
            label: const Text('Copy heads-up plan'),
          ),
        ),
      ]),
    );
  }
}

/// First run (2e): the shape of what you are about to fill, drawn as dashed outlines, with the
/// wizard docked at the bottom so the map is visible behind it the whole time.
class _FirstRunCanvas extends StatelessWidget {
  final ApiClient api;
  final OpenFn? open;
  final VoidCallback onDone;
  const _FirstRunCanvas({required this.api, required this.open, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return _CanvasBackdrop(
      bands: false,
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GhostEstatePainter())),
        Positioned(
          left: 0,
          right: 0,
          top: 96,
          child: Column(children: [
            const BrandMark(size: 34),
            const SizedBox(height: 18),
            Text('Let’s map your estate', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            const SizedBox(
              width: 430,
              child: Text(
                'Two connections and one sync. Nothing here is a one-way door — you can change '
                'any of it later from Sources.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.6, color: AppColors.textMuted),
              ),
            ),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                child: FirstRunWizard(api: api, open: open ?? (_, {api, endpoint, field}) {},
                    onDone: onDone),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Dashed node outlines and dashed edges: the silhouette of an estate that has not been synced yet.
class _GhostEstatePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.12);
    final cy = size.height * 0.42;
    final slots = [
      Rect.fromLTWH(size.width * 0.10, cy - 40, 110, 40),
      Rect.fromLTWH(size.width * 0.10, cy + 40, 110, 40),
      Rect.fromLTWH(size.width * 0.38, cy - 60, 200, 40),
      Rect.fromLTWH(size.width * 0.38, cy + 20, 200, 40),
      Rect.fromLTWH(size.width * 0.70, cy - 20, 160, 40),
    ];
    for (final r in slots) {
      _dashedRRect(canvas, RRect.fromRectAndRadius(r, const Radius.circular(9)), stroke);
    }
  }

  void _dashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GhostEstatePainter oldDelegate) => false;
}
