import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Quad, Vector3;

import '../api.dart';
import '../main.dart';
import '../pins.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/global_search.dart';
import '../widgets/skeleton.dart';
import 'first_run.dart';

/// The estate canvas — the home surface. The map is not a tab you visit; it is the ground the
/// whole product sits on, with everything else docked over it as glass.
class GraphScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn? open;

  /// Node to open focused, from a shared link.
  final String? initialFocus;
  const GraphScreen({super.key, required this.api, this.open, this.initialFocus});

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
  bool _riskOnly = false;

  /// Replaced wholesale rather than mutated: `_Estate` compares old and new to decide whether to
  /// re-lay the map, and an in-place edit leaves both sides pointing at the same Set.
  Set<String> _hiddenLayers = const {};

  @override
  void initState() {
    super.initState();
    // A shared #/estate/<api> link lands straight in focus mode on that node.
    _focused = widget.initialFocus;
    // The map outlives navigation now, so it has to be told when a sync has replaced the estate
    // underneath it — otherwise you sync a new repo and the map still shows the old one.
    ApiClient.estateRevision.addListener(_onEstateChanged);
    _load();
  }

  void _onEstateChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    ApiClient.estateRevision.removeListener(_onEstateChanged);
    super.dispose();
  }

  void _load() {
    setState(() {
      _graph = widget.api.graph();
      _insights = widget.api.insights().catchError((_) => <InsightFinding>[]);
    });
  }

  /// The shell watches [FocusState] and mirrors it into the address bar, so the link stays
  /// copy-pasteable without the canvas knowing about routing.
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
          riskOnly: _riskOnly,
          hiddenLayers: _hiddenLayers,
          onFocus: _focus,
          onDirection: (d) => setState(() => _direction = d),
          onGovernance: (v) => setState(() => _governance = v),
          onRiskOnly: (v) => setState(() => _riskOnly = v),
          onToggleLayer: (l) => setState(() {
            _hiddenLayers = _hiddenLayers.contains(l)
                ? ({..._hiddenLayers}..remove(l))
                : {..._hiddenLayers, l};
          }),
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
        // Without its own layer the sweep is a full-screen repaint sixty times a second — and
        // because it shares a Stack with the map, it dragged every node and edge into that repaint.
        if (!reduce)
          Positioned.fill(
            child: RepaintBoundary(
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
          ),
        Positioned.fill(child: RepaintBoundary(child: widget.child)),
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

/// Column geometry from the comp: x-origins 60 / 330 / 630 / 890 with per-layer widths, rows on a
/// 120px pitch starting at y=276.
///
/// A layer wider than [rowsFor] wraps into further sub-columns rather than running off the bottom.
/// A real Anypoint org is ~1000 assets, so a single column per layer meant a 24,000px wall that
/// could only be read by scrolling for a minute — the demo estate still lays out exactly as before,
/// because a layer that fits in one column never wraps.
class _Layout {
  static const layers = ['APP', 'EXPERIENCE', 'PROCESS', 'SYSTEM', 'BACKEND'];
  static const widths = [190.0, 220.0, 220.0, 190.0, 190.0];
  static const gutters = [80.0, 80.0, 40.0, 80.0];
  static const subGutter = 26.0;
  static const rowTop = 276.0;
  static const rowPitch = 120.0;
  static const nodeHeight = 62.0;
  static const headerOffset = 66.0;
  static const nodeAnchor = 24.0;

  /// Rows per sub-column, chosen so the whole canvas lands near a 2:1 aspect whatever the estate
  /// size. Solved from `bandWidth ≈ 2 × bandHeight`; the floor keeps small estates single-column
  /// and therefore pixel-identical to the comp.
  static int rowsFor(int biggestLayer) {
    if (biggestLayer <= 1) return 6;
    final r = (-672 + math.sqrt(451584 + 1200000 * biggestLayer)) / 480;
    return r.ceil().clamp(6, 60);
  }
}

class _Placed {
  final GraphNode node;
  final double x;
  final double y;
  final double width;
  const _Placed(this.node, this.x, this.y, this.width);

  Offset get leftAnchor => Offset(x, y + _Layout.nodeAnchor);
  Offset get rightAnchor => Offset(x + width, y + _Layout.nodeAnchor);
  Rect get rect => Rect.fromLTWH(x, y, width, _Layout.nodeHeight);
}

/// One layer's slot on the canvas, after wrapping.
class _Band {
  final String layer;
  final double x;
  final double width;
  final int columns;
  final int count;
  const _Band(this.layer, this.x, this.width, this.columns, this.count);
}

class _Estate extends StatefulWidget {
  final ApiClient api;
  final GraphDto graph;
  final Future<List<InsightFinding>> insights;
  final String? focused;
  final FocusDirection direction;
  final bool governance;
  final bool riskOnly;
  final Set<String> hiddenLayers;
  final ValueChanged<String?> onFocus;
  final ValueChanged<FocusDirection> onDirection;
  final ValueChanged<bool> onGovernance;
  final ValueChanged<bool> onRiskOnly;
  final ValueChanged<String> onToggleLayer;
  final OpenFn? open;

  const _Estate({
    required this.api,
    required this.graph,
    required this.insights,
    required this.focused,
    required this.direction,
    required this.governance,
    required this.riskOnly,
    required this.hiddenLayers,
    required this.onFocus,
    required this.onDirection,
    required this.onGovernance,
    required this.onRiskOnly,
    required this.onToggleLayer,
    required this.open,
  });

  @override
  State<_Estate> createState() => _EstateState();
}

class _EstateState extends State<_Estate> with TickerProviderStateMixin {
  /// One transform for both axes. The map used to be a vertical scroll view wrapping a horizontal
  /// one, which cannot pan diagonally, gave the horizontal axis no scrollbar, and — because Flutter
  /// scrollables ignore mouse drags — left the right-hand columns unreachable with a mouse.
  final _tc = TransformationController();
  Size _viewport = Size.zero;
  bool _fitted = false;

  /// Drives the marching dashes on breaking edges. Only ever run while dashes are actually on
  /// screen: a repeating controller repaints the whole edge layer 60 times a second.
  late final AnimationController _dash =
      AnimationController(vsync: this, duration: AppMotion.edgeFlow);

  /// Drives the staggered path reveal in focus mode.
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1550));

  late final AnimationController _breathe =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  final _positions = <String, _Placed>{};
  final _bands = <_Band>[];
  double _canvasW = 1400;
  double _canvasH = 900;

  // ---- indexes, rebuilt only when the graph itself changes ----
  /// Nodes with a breaking edge, and nodes whose every edge is app-to-app only. Recomputing these
  /// per node per build was an O(nodes × edges) scan on every frame of the focus reveal.
  final _breakingNodes = <String>{};
  final _shallowNodes = <String>{};
  final _out = <String, List<GraphEdge>>{};
  final _in = <String, List<GraphEdge>>{};

  /// Edges split by how they are drawn, so the animated layer only ever walks the few that march.
  final _staticEdges = <GraphEdge>[];
  final _liveEdges = <GraphEdge>[];

  // ---- the focus path, recomputed only when focus or direction changes ----
  List<GraphEdge> _pathEdges = const [];
  Set<GraphEdge> _pathEdgeSet = const {};
  Map<GraphEdge, int> _hopOfEdge = const {};
  Set<String> _onPath = const {};
  Map<String, int> _hopOfNode = const {};

  /// The right-hand panel is glass docked over the map. It can be folded away, and everything it
  /// covers can now be panned out from under it.
  bool _panelsOpen = true;

  /// Above this many cards in view, names are unreadable anyway — draw plates instead of widgets.
  static const _cardBudget = 260;

  /// (drawing plates, nodes in view). Published from inside the transform builder, so the hint that
  /// explains the plates is written a frame later rather than mid-layout.
  final _density = ValueNotifier<(bool, int)>((false, 0));

  @override
  void initState() {
    super.initState();
    _index();
    _place();
    _computePath();
    _rememberEstate();
    if (widget.focused != null) {
      _reveal.forward();
      _breathe.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _Estate old) {
    super.didUpdateWidget(old);
    final graphChanged = old.graph != widget.graph;
    if (graphChanged) {
      _index();
      _rememberEstate();
    }
    if (graphChanged ||
        old.riskOnly != widget.riskOnly ||
        !setEquals(old.hiddenLayers, widget.hiddenLayers)) {
      _place();
      _fitted = false;
    }
    if (graphChanged ||
        old.focused != widget.focused ||
        old.direction != widget.direction) {
      _computePath();
    }
    if (old.focused != widget.focused) {
      if (widget.focused == null) {
        _reveal.reset();
        _breathe.stop();
      } else {
        _reveal.forward(from: 0);
        if (!_breathe.isAnimating) _breathe.repeat();
        // Focusing from search or a shared link used to leave the viewport wherever it was, so on
        // a large estate the node you just picked was somewhere off screen.
        WidgetsBinding.instance.addPostFrameCallback((_) => _centreOn(widget.focused!));
      }
    }
  }

  @override
  void dispose() {
    _dash.dispose();
    _reveal.dispose();
    _breathe.dispose();
    _tc.dispose();
    _density.dispose();
    super.dispose();
  }

  List<String> get _apiIds =>
      widget.graph.nodes.where((n) => n.api).map((n) => n.id).toList();

  /// A first-ever look is the baseline, not a change: without it every API in the estate would be
  /// reported as new the first time the map was opened.
  void _rememberEstate() => EstateDelta.rememberFirstLook(_apiIds);

  /// Everything derived from the edge list, computed once per graph.
  void _index() {
    _breakingNodes.clear();
    _shallowNodes.clear();
    _out.clear();
    _in.clear();
    _staticEdges.clear();
    _liveEdges.clear();

    final deep = <String>{};
    final touched = <String>{};
    for (final e in widget.graph.edges) {
      (_out[e.from] ??= []).add(e);
      (_in[e.to] ??= []).add(e);
      touched.add(e.from);
      touched.add(e.to);
      if (e.risk == 'breaking') {
        _breakingNodes.add(e.from);
        _breakingNodes.add(e.to);
        _liveEdges.add(e);
      } else {
        _staticEdges.add(e);
      }
      if (e.endpointLevel) {
        deep.add(e.from);
        deep.add(e.to);
      }
    }
    for (final id in touched) {
      if (!deep.contains(id)) _shallowNodes.add(id);
    }
  }

  /// RISK narrows the map to the nodes actually on a breaking edge; LAYERS hides whole columns.
  /// Both matter once an estate outgrows a single screen.
  bool _passesFilters(GraphNode n) {
    if (widget.hiddenLayers.contains(n.layer)) return false;
    if (widget.riskOnly) return _breakingNodes.contains(n.id);
    return true;
  }

  void _place() {
    _positions.clear();
    _bands.clear();

    final byLayer = <String, List<GraphNode>>{for (final l in _Layout.layers) l: []};
    final unclassified = <GraphNode>[];
    for (final n in widget.graph.nodes) {
      if (!_passesFilters(n)) continue;
      final bucket = byLayer[n.layer];
      (bucket ?? unclassified).add(n);
    }
    // An unrecognised layer used to be parked at the same coordinates as the BACKEND column, so the
    // two drew on top of each other. It gets its own band instead.
    final groups = [
      for (int i = 0; i < _Layout.layers.length; i++)
        (_Layout.layers[i], byLayer[_Layout.layers[i]]!, _Layout.widths[i],
            i < _Layout.gutters.length ? _Layout.gutters[i] : 80.0),
      if (unclassified.isNotEmpty) ('UNKNOWN', unclassified, 190.0, 80.0),
    ];

    final biggest = groups.fold<int>(0, (m, g) => math.max(m, g.$2.length));
    final rows = _Layout.rowsFor(biggest);

    double x = 60;
    double right = 60;
    int tallest = 1;
    for (final (layer, nodes, width, gutter) in groups) {
      // List.sort is not stable, so equal-degree nodes would take different rows on every re-lay
      // and the map appeared to shuffle itself. The id is the tiebreaker.
      nodes.sort((a, b) {
        final byDegree = b.dependedOnBy.compareTo(a.dependedOnBy);
        return byDegree != 0 ? byDegree : a.id.compareTo(b.id);
      });
      final columns = nodes.isEmpty ? 1 : (nodes.length / rows).ceil();
      for (int k = 0; k < nodes.length; k++) {
        _positions[nodes[k].id] = _Placed(
          nodes[k],
          x + (k ~/ rows) * (width + _Layout.subGutter),
          _Layout.rowTop + (k % rows) * _Layout.rowPitch,
          width,
        );
      }
      if (nodes.isNotEmpty) {
        _bands.add(_Band(layer, x, width, columns, nodes.length));
        tallest = math.max(tallest, math.min(nodes.length, rows));
        right = x + columns * width + (columns - 1) * _Layout.subGutter;
      }
      x += columns * width + (columns - 1) * _Layout.subGutter + gutter;
    }

    _canvasW = right + 60;
    _canvasH = _Layout.rowTop + tallest * _Layout.rowPitch + 60;
  }

  /// Edges on the blast path, in hop order, so the reveal can stagger by distance. Walks the
  /// adjacency index rather than the whole edge list per frontier.
  void _computePath() {
    final root = widget.focused;
    if (root == null) {
      _pathEdges = const [];
      _pathEdgeSet = const {};
      _hopOfEdge = const {};
      _onPath = const {};
      _hopOfNode = const {};
      return;
    }
    final edges = <GraphEdge>[];
    final hops = <GraphEdge, int>{};
    final nodeHop = <String, int>{root: 0};
    final seen = <String>{root};
    var frontier = <String>{root};
    int hop = 0;
    final down = widget.direction != FocusDirection.upstream;
    final up = widget.direction != FocusDirection.downstream;
    while (frontier.isNotEmpty) {
      hop++;
      final next = <String>{};
      for (final id in frontier) {
        if (down) {
          for (final e in _in[id] ?? const <GraphEdge>[]) {
            if (seen.add(e.from)) {
              hops[e] = edges.length;
              edges.add(e);
              nodeHop[e.from] = hop;
              next.add(e.from);
            }
          }
        }
        if (up) {
          for (final e in _out[id] ?? const <GraphEdge>[]) {
            if (seen.add(e.to)) {
              hops[e] = edges.length;
              edges.add(e);
              nodeHop[e.to] = hop;
              next.add(e.to);
            }
          }
        }
      }
      frontier = next;
    }
    _pathEdges = edges;
    _pathEdgeSet = edges.toSet();
    _hopOfEdge = hops;
    _onPath = seen;
    _hopOfNode = nodeHop;
  }

  /// Corner panels clear the centred command bar once the window is too narrow to sit beside it.
  static double _cornerBottom(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 1150 ? 96 : 30;

  /// The area of the viewport the docked glass does not sit on.
  EdgeInsets get _chrome => EdgeInsets.fromLTRB(24, 92, _panelsOpen ? 356 : 64, 132);

  double get _scale => _tc.value.getMaxScaleOnAxis();

  void _setScale(double next, {Offset? focalPoint}) {
    final clamped = next.clamp(0.18, 2.5);
    final pivot = focalPoint ??
        Offset(_chrome.left + (_viewport.width - _chrome.horizontal) / 2,
            _chrome.top + (_viewport.height - _chrome.vertical) / 2);
    final before = _toCanvas(pivot);
    final m = Matrix4.identity()
      ..translate(pivot.dx - before.dx * clamped, pivot.dy - before.dy * clamped)
      ..scale(clamped);
    _tc.value = m;
  }

  Offset _toCanvas(Offset viewportPoint) {
    final inverted = Matrix4.inverted(_tc.value);
    final v = inverted.transform3(Vector3(viewportPoint.dx, viewportPoint.dy, 0));
    return Offset(v.x, v.y);
  }

  /// Fit the estate into the part of the window the panels leave free — never so far out that the
  /// node names stop being readable; a huge estate opens at its top-left instead.
  void _fit() {
    if (_viewport == Size.zero) return;
    final w = _viewport.width - _chrome.horizontal;
    final h = _viewport.height - _chrome.vertical;
    if (w <= 0 || h <= 0) return;
    final s = math.min(w / _canvasW, h / _canvasH).clamp(0.32, 1.0);
    final dx = _chrome.left + math.max(0, (w - _canvasW * s) / 2);
    final dy = _chrome.top + math.max(0, (h - _canvasH * s) / 2);
    _tc.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(s);
  }

  /// Bring a node into the free area without changing zoom.
  void _centreOn(String id) {
    final p = _positions[id];
    if (p == null || _viewport == Size.zero) return;
    final s = _scale;
    final cx = _chrome.left + (_viewport.width - _chrome.horizontal) / 2;
    final cy = _chrome.top + (_viewport.height - _chrome.vertical) / 2;
    final target = Offset(p.x + p.width / 2, p.y + _Layout.nodeHeight / 2);
    _tc.value = Matrix4.identity()
      ..translate(cx - target.dx * s, cy - target.dy * s)
      ..scale(s);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final focusing = widget.focused != null;

    // Publish focus upward so the shell's bar can take it over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusState.instance;
      focus.onClose = () => widget.onFocus(null);
      focus.onOpenHub = () => widget.open?.call(Tabs.apiHub, api: widget.focused);
      focus.onDirection = (i) => widget.onDirection(FocusDirection.values[i]);
      focus.set(widget.focused,
          hops: _pathEdges.length,
          nodes: _onPath.length,
          direction: widget.direction.index);
    });

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
          // ---- the map itself: one surface, panned and zoomed in both axes at once ----
          Positioned.fill(
            child: LayoutBuilder(builder: (context, c) {
              if (_viewport != c.biggest) {
                // Only the first layout fits automatically. Refitting on every resize would throw
                // away the viewport the user had just arranged the moment they dragged the window.
                final first = _viewport == Size.zero;
                _viewport = c.biggest;
                if (first) _fitted = false;
              }
              if (!_fitted) {
                _fitted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (widget.focused != null) {
                    _centreOn(widget.focused!);
                  } else {
                    _fit();
                  }
                });
              }
              return InteractiveViewer.builder(
                transformationController: _tc,
                minScale: 0.18,
                maxScale: 2.5,
                // A finite margin is a scale-dependent leash: zoomed out, the viewport in canvas
                // coordinates is wider than the estate and the map refuses to move far enough to
                // clear the docked panel. Unbounded panning with a Fit control is the honest pair.
                boundaryMargin: const EdgeInsets.all(double.infinity),
                builder: (context, quad) => _canvas(context, quad, focusing, reduce),
              );
            }),
          ),

          // ---- docked chrome ----
          // The comp docks these three at bottom:30 across a 1440px bar. Narrower than ~1150 the
          // centred command bar runs into the corner panels, so they step up above it instead of
          // overlapping — the map is a console, and chrome must never cover chrome.
          if (!focusing) ...[
            Positioned(
                left: 28, bottom: _cornerBottom(context), child: _SummaryPanel(graph: widget.graph)),
            Positioned(
              right: 28,
              top: 92,
              width: _panelsOpen ? 300 : 44,
              child: _AttentionStack(
                insights: widget.insights,
                graph: widget.graph,
                governance: widget.governance,
                open: _panelsOpen,
                onToggle: () => setState(() => _panelsOpen = !_panelsOpen),
                onAcknowledge: () => setState(() {}),
                onOpen: (api) => widget.onFocus(api),
              ),
            ),
          ],
          if (focusing)
            Positioned(
              right: 28,
              bottom: _cornerBottom(context),
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
              bottom: _cornerBottom(context),
              child: AnimatedBuilder(
                animation: _tc,
                builder: (context, _) => _ZoomCluster(
                  scale: _scale,
                  onZoom: (d) => _setScale(_scale + d),
                  onFit: _fit,
                ),
              ),
            ),
          // At estate scale the map is a shape, not a list of names. Say so, rather than leaving the
          // user to wonder why the cards turned into plates.
          Positioned(
            left: 0,
            right: 0,
            top: 92,
            child: Center(
              child: ValueListenableBuilder<(bool, int)>(
                valueListenable: _density,
                builder: (context, value, _) {
                  final (plates, shown) = value;
                  if (!plates || focusing) return const SizedBox.shrink();
                  return GlassPanel(
                    radius: AppRadius.pill,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Text(
                      'Showing $shown of ${widget.graph.nodes.length} APIs · '
                      'Zoom in to read names, or search for one',
                      style: monoData(size: 10.5),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 30,
            child: Center(
              child: _CommandBar(
                governance: widget.governance,
                riskOnly: widget.riskOnly,
                hiddenLayers: widget.hiddenLayers,
                focusing: focusing,
                onGovernance: widget.onGovernance,
                onRiskOnly: widget.onRiskOnly,
                onToggleLayer: widget.onToggleLayer,
                onExitFocus: () => widget.onFocus(null),
                onSearch: () async {
                  final sel = await showGlobalSearch(context, widget.api);
                  if (sel != null) widget.onFocus(sel.api);
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// The transformed canvas. Only what the viewport actually covers is built — a thousand-node
  /// estate is otherwise a thousand live widgets and every edge in the estate, every frame.
  Widget _canvas(BuildContext context, Quad quad, bool focusing, bool reduce) {
    final view = _viewRect(quad);
    final margin = view.inflate(240);

    final visible = <_Placed>[];
    for (final p in _positions.values) {
      if (margin.overlaps(p.rect)) visible.add(p);
    }
    // Zoomed out far enough that names cannot be read, plates carry the same information for a
    // fraction of the cost, and the map stays draggable instead of stuttering.
    final plates = visible.length > _cardBudget;
    final density = (plates, visible.length);
    if (_density.value != density) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _density.value = density;
      });
    }

    final liveEdges = <GraphEdge>[];
    for (final e in _liveEdges) {
      if (_edgeVisible(e, margin)) liveEdges.add(e);
    }
    final pathVisible = <GraphEdge>[];
    for (final e in _pathEdges) {
      if (_edgeVisible(e, margin)) pathVisible.add(e);
    }
    // A marching dash is an attention cue. Forty of them at once is not a cue, and each one costs a
    // path walk per frame — past that they are drawn solid, which reads better anyway.
    final animate = !reduce &&
        (pathVisible.isNotEmpty ||
            (liveEdges.isNotEmpty && liveEdges.length <= 40));
    _syncDash(animate && liveEdges.isNotEmpty);

    Widget edgeLayer = CustomPaint(
      size: Size(_canvasW, _canvasH),
      painter: _StaticEdgePainter(
        edges: _staticEdges,
        positions: _positions,
        view: margin,
        focusing: focusing,
        pathEdges: _pathEdgeSet,
      ),
    );

    Widget liveLayer(double dash, double reveal) => CustomPaint(
          size: Size(_canvasW, _canvasH),
          painter: _LiveEdgePainter(
            breaking: liveEdges,
            pathEdges: pathVisible,
            hopOfEdge: _hopOfEdge,
            positions: _positions,
            focusing: focusing,
            pathSet: _pathEdgeSet,
            dash: dash,
            reveal: reveal,
            marching: animate,
          ),
        );

    return SizedBox(
      width: _canvasW,
      height: _canvasH,
      child: Stack(children: [
        if (focusing && _positions[widget.focused] != null)
          Positioned(
            left: _positions[widget.focused]!.x - 450 + 110,
            top: _positions[widget.focused]!.y - 450 + 24,
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
        RepaintBoundary(child: edgeLayer),
        RepaintBoundary(
          child: animate
              ? AnimatedBuilder(
                  animation: Listenable.merge([_dash, _reveal]),
                  builder: (context, _) => liveLayer(_dash.value, _reveal.value),
                )
              : liveLayer(0, 1),
        ),
        for (final band in _bands)
          Positioned(
            left: band.x,
            top: _Layout.rowTop - _Layout.headerOffset,
            child: Text(
              '${AppColors.layerBand(band.layer)} · ${band.count}',
              style: monoLabel(
                size: 10,
                color: AppColors.forLayer(band.layer).withOpacity(focusing ? 0.5 : 1),
              ),
            ),
          ),
        if (plates)
          Positioned.fill(
            child: GestureDetector(
              // A CustomPaint does not answer hit tests by itself, so deferring to it would make
              // plates unclickable. Panning still works: the viewer sits above this in the path.
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final hit = _nodeAt(d.localPosition);
                if (hit != null) widget.onFocus(hit == widget.focused ? null : hit);
              },
              child: CustomPaint(
                painter: _NodePlatePainter(
                  nodes: visible,
                  breaking: _breakingNodes,
                  focused: widget.focused,
                  onPath: _onPath,
                  focusing: focusing,
                ),
              ),
            ),
          )
        else
          for (final placed in visible) _positionedNode(placed, focusing, reduce),
      ]),
    );
  }

  /// Only run the dash controller while dashes are on screen.
  void _syncDash(bool wanted) {
    if (wanted == _dash.isAnimating) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (wanted) {
        if (!_dash.isAnimating) _dash.repeat();
      } else {
        _dash.stop();
      }
    });
  }

  Rect _viewRect(Quad quad) {
    final xs = [quad.point0.x, quad.point1.x, quad.point2.x, quad.point3.x];
    final ys = [quad.point0.y, quad.point1.y, quad.point2.y, quad.point3.y];
    return Rect.fromLTRB(
        xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
  }

  bool _edgeVisible(GraphEdge e, Rect view) {
    final a = _positions[e.from];
    final b = _positions[e.to];
    if (a == null || b == null) return false;
    return view.overlaps(Rect.fromPoints(a.rightAnchor, b.leftAnchor).inflate(4));
  }

  String? _nodeAt(Offset canvasPoint) {
    for (final p in _positions.values) {
      if (p.rect.contains(canvasPoint)) return p.node.id;
    }
    return null;
  }

  Widget _positionedNode(_Placed placed, bool focusing, bool reduce) {
    final isFocus = placed.node.id == widget.focused;
    final lit = !focusing || _onPath.contains(placed.node.id);

    Widget card = _NodeCard(
      node: placed.node,
      focused: isFocus,
      dimmed: focusing && !lit,
      breaking: _breakingNodes.contains(placed.node.id),
      shallowOnly: _shallowNodes.contains(placed.node.id),
      breathe: isFocus ? _breathe : null,
      onTap: () => widget.onFocus(isFocus ? null : placed.node.id),
      onOpen: () => widget.open?.call(Tabs.apiHub, api: placed.node.id),
    );

    // Each node arrives 400ms after its incoming edge starts drawing. Driving that from the
    // controller directly rather than rebuilding the layer per frame is the difference between a
    // reveal and a stall: the old AnimatedBuilder rebuilt every card on screen sixty times a second.
    if (focusing && lit && !reduce) {
      final start = ((0.10 + (_hopOfNode[placed.node.id] ?? 0) * 0.25) / 1.55).clamp(0.0, 0.88);
      card = FadeTransition(
        opacity: _reveal.drive(CurveTween(curve: Interval(start, math.min(start + 0.12, 1.0)))),
        child: card,
      );
    }

    return Positioned(
      left: placed.x,
      top: placed.y,
      width: placed.width,
      child: card,
    );
  }
}

/// Consumer -> provider reads left to right, so an edge leaves the consumer's right edge.
Path _edgePath(_Placed from, _Placed to) {
  final a = from.rightAnchor;
  final b = to.leftAnchor;
  final dx = (b.dx - a.dx).abs() / 2;
  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
}

/// Everything that never moves: the quiet estate wiring. Split out from the animated layer so a
/// thousand béziers are not re-stroked sixty times a second for the sake of a few dashes.
class _StaticEdgePainter extends CustomPainter {
  final List<GraphEdge> edges;
  final Map<String, _Placed> positions;
  final Rect view;
  final bool focusing;
  final Set<GraphEdge> pathEdges;

  _StaticEdgePainter({
    required this.edges,
    required this.positions,
    required this.view,
    required this.focusing,
    required this.pathEdges,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.05);
    final safe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = AppColors.additive.withOpacity(0.45);
    final quiet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = Colors.white.withOpacity(0.12);

    for (final e in edges) {
      final from = positions[e.from];
      final to = positions[e.to];
      if (from == null || to == null) continue;
      if (!view.overlaps(Rect.fromPoints(from.rightAnchor, to.leftAnchor).inflate(4))) continue;
      // On-path edges belong to the animated layer; off-path ones fade back during focus.
      if (focusing && pathEdges.contains(e)) continue;
      final path = _edgePath(from, to);
      canvas.drawPath(path, focusing ? dim : (e.risk == 'safe' ? safe : quiet));
    }
  }

  @override
  bool shouldRepaint(covariant _StaticEdgePainter old) =>
      old.edges != edges ||
      old.focusing != focusing ||
      old.pathEdges != pathEdges ||
      old.view != view;
}

/// The few edges that carry motion: breaking edges march, and the focus reveal draws each on-path
/// edge from nothing over 500ms, staggered 250ms in hop order.
class _LiveEdgePainter extends CustomPainter {
  final List<GraphEdge> breaking;
  final List<GraphEdge> pathEdges;
  final Map<GraphEdge, int> hopOfEdge;
  final Map<String, _Placed> positions;
  final Set<GraphEdge> pathSet;
  final bool focusing;
  final double dash;
  final double reveal;
  final bool marching;

  _LiveEdgePainter({
    required this.breaking,
    required this.pathEdges,
    required this.hopOfEdge,
    required this.positions,
    required this.pathSet,
    required this.focusing,
    required this.dash,
    required this.reveal,
    required this.marching,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (focusing) {
      for (final e in pathEdges) {
        final from = positions[e.from];
        final to = positions[e.to];
        if (from == null || to == null) continue;
        final i = hopOfEdge[e] ?? 0;
        final start = (0.10 + i * 0.25) / 1.55;
        final end = start + (0.5 / 1.55);
        final t = marching ? ((reveal - start) / (end - start)).clamp(0.0, 1.0) : 1.0;
        if (t <= 0) continue;
        final isBreaking = e.risk == 'breaking';
        canvas.drawPath(
            _partial(_edgePath(from, to), t),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isBreaking ? 2 : 1.6
              ..color = isBreaking ? AppColors.breaking : AppColors.warning);
      }
      return;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.breaking;
    for (final e in breaking) {
      final from = positions[e.from];
      final to = positions[e.to];
      if (from == null || to == null) continue;
      final path = _edgePath(from, to);
      if (marching) {
        _dashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  /// 7-on / 9-off marching dashes. The brief travels dashoffset to -320 over the 6s cycle — a
  /// single 16px period per cycle reads as static, which is what it looked like before.
  void _dashed(Canvas canvas, Path path, Paint paint) {
    const on = 7.0, off = 9.0;
    final phase = -320.0 * dash;
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
    if (t >= 1.0) return path;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(metric.extractPath(0, metric.length * t), Offset.zero);
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _LiveEdgePainter old) =>
      old.dash != dash ||
      old.reveal != reveal ||
      old.focusing != focusing ||
      old.marching != marching ||
      old.breaking != breaking ||
      old.pathEdges != pathEdges;
}

/// Zoomed far enough out that a name cannot be read, a node is a plate: same position, same layer
/// colour, same risk, none of the cost of a live widget per API.
class _NodePlatePainter extends CustomPainter {
  final List<_Placed> nodes;
  final Set<String> breaking;
  final Set<String> onPath;
  final String? focused;
  final bool focusing;

  _NodePlatePainter({
    required this.nodes,
    required this.breaking,
    required this.onPath,
    required this.focused,
    required this.focusing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = AppColors.nodeQuiet;
    final dimFill = Paint()..color = AppColors.nodeOffPath;
    for (final p in nodes) {
      final lit = !focusing || onPath.contains(p.node.id);
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(p.x, p.y, p.width, _Layout.nodeHeight),
          const Radius.circular(AppRadius.tile));
      canvas.drawRRect(rect, lit ? fill : dimFill);

      final layer = AppColors.forLayer(p.node.layer);
      final isFocus = p.node.id == focused;
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocus ? 2 : 1
        ..color = isFocus
            ? AppColors.breaking
            : (breaking.contains(p.node.id)
                ? AppColors.breaking.withOpacity(lit ? 0.5 : 0.2)
                : layer.withOpacity(lit ? 0.35 : 0.12));
      canvas.drawRRect(rect, border);

      // The layer dot is the one mark that still carries meaning at this size.
      canvas.drawCircle(Offset(p.x + 14, p.y + 20), 3.5,
          Paint()..color = layer.withOpacity(lit ? 0.9 : 0.3));
      canvas.drawRect(
          Rect.fromLTWH(p.x + 26, p.y + 17, math.min(p.width - 46, 96), 6),
          Paint()..color = Colors.white.withOpacity(lit ? 0.16 : 0.06));
    }
  }

  @override
  bool shouldRepaint(covariant _NodePlatePainter old) =>
      old.nodes != nodes ||
      old.focused != focused ||
      old.focusing != focusing ||
      old.onPath != onPath;
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
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onAcknowledge;
  final ValueChanged<String> onOpen;
  const _AttentionStack({
    required this.insights,
    required this.graph,
    required this.governance,
    required this.open,
    required this.onToggle,
    required this.onAcknowledge,
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
    // Docked glass sits on top of the map. It has to be foldable, or the estate under it is a part
    // of the map you can see the shape of but never read.
    final toggle = Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: open ? 'Fold this panel away' : 'Show what needs a decision',
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 44,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.glassStrong,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.hairlineStrong),
            ),
            child: Icon(open ? Icons.chevron_right : Icons.chevron_left,
                size: 18, color: AppColors.textMuted),
          ),
        ),
      ),
    );
    if (!open) return toggle;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      toggle,
      const SizedBox(height: 8),
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
            Row(children: [
              Text('SINCE YOU LAST LOOKED', style: monoLabel()),
              const Spacer(),
              // A sync can add hundreds of APIs at once. Listing three of them and stopping reads
              // as "three arrived", which is the opposite of what happened.
              if (delta.added.length + delta.removed.length > 5)
                Text('${delta.added.length}+ / ${delta.removed.length}−',
                    style: monoData(size: 10)),
            ]),
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
            if (delta.added.length > 3 || delta.removed.length > 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'and ${delta.added.length - math.min(3, delta.added.length) + delta.removed.length - math.min(2, delta.removed.length)} more',
                    style: monoData(size: 11)),
              ),
            // Nothing ever cleared this list, so once it appeared it stayed for good.
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  EstateDelta.remember(ids);
                  onAcknowledge();
                },
                child: const Text('Got it'),
              ),
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
  final bool riskOnly;
  final Set<String> hiddenLayers;
  final bool focusing;
  final ValueChanged<bool> onGovernance;
  final ValueChanged<bool> onRiskOnly;
  final ValueChanged<String> onToggleLayer;
  final VoidCallback onExitFocus;
  final VoidCallback onSearch;
  const _CommandBar({
    required this.governance,
    required this.riskOnly,
    required this.hiddenLayers,
    required this.focusing,
    required this.onGovernance,
    required this.onRiskOnly,
    required this.onToggleLayer,
    required this.onExitFocus,
    required this.onSearch,
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
    // The bar was a fixed-width Row (a 250px search well plus five words), so it overflowed the
    // window below ~800px — half a 1536px laptop screen. It now sheds the search caption, then the
    // shortcut chip, then the least-used filter word.
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final showCaption = w >= 860;
      final showChip = w >= 780;
      final showGovernance = w >= 660;
      final captionWidth = w >= 1024 ? 250.0 : 150.0;

      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, 12))
          ],
        ),
        child: GlassPanel(
          radius: 14,
          strong: true,
          border: AppColors.hairlineStrong,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // It looks exactly like a search box, so it has to behave like one.
            Tooltip(
              message: showCaption ? '' : 'Search APIs, endpoints, fields  (Ctrl/Cmd-K)',
              child: InkWell(
                onTap: onSearch,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search, size: 17, color: AppColors.textFaint),
                    if (showCaption) ...[
                      const SizedBox(width: 14),
                      SizedBox(
                        width: captionWidth,
                        child: const Text('Search APIs, endpoints, fields…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: AppColors.textFaint)),
                      ),
                    ],
                    if (showChip)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.hairlineStrong),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('⌘K', style: monoData(size: 10)),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 20, color: AppColors.hairlineStrong),
            const SizedBox(width: 12),
            if (showGovernance) ...[
              word('GOVERNANCE', active: governance, onTap: () => onGovernance(!governance)),
              const SizedBox(width: 8),
            ],
            word('RISK', active: riskOnly, onTap: () => onRiskOnly(!riskOnly)),
            const SizedBox(width: 8),
            _LayersMenu(hidden: hiddenLayers, onToggle: onToggleLayer),
            // FOCUS MODE only ever did anything while focusing; as a permanent word styled like its
            // live neighbours it was a control that could not be used. It now appears only when
            // there is a focus to leave.
            if (focusing) ...[
              const SizedBox(width: 8),
              word('EXIT FOCUS', active: true, onTap: onExitFocus),
            ],
          ]),
        ),
      );
    });
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
class _WhoToTell extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  final GraphDto graph;
  const _WhoToTell({required this.api, required this.apiId, required this.graph});

  @override
  State<_WhoToTell> createState() => _WhoToTellState();
}

class _WhoToTellState extends State<_WhoToTell> {
  Future<Reach>? _reach;

  @override
  void initState() {
    super.initState();
    _reach = widget.api.reach(widget.apiId);
  }

  @override
  void didUpdateWidget(covariant _WhoToTell old) {
    super.didUpdateWidget(old);
    if (old.apiId != widget.apiId) _reach = widget.api.reach(widget.apiId);
  }

  @override
  Widget build(BuildContext context) {
    final apiId = widget.apiId;
    final graph = widget.graph;
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
        // Direct consumers are who you must tell; everything further out is who is downwind of
        // them. Naming the second number stops "2 consumers" reading as the whole story.
        FutureBuilder<Reach>(
          future: _reach,
          builder: (context, snap) {
            final onward = snap.data?.transitive.length ?? 0;
            if (onward == 0) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.fillSubtle,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(children: [
                const Icon(Icons.share_outlined, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '$onward more API${onward == 1 ? "" : "s"} sit downwind of these — affected '
                    'only if their provider passes the change on.',
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.45, color: AppColors.textMuted),
                  ),
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final b = StringBuffer('Heads-up: $apiId is changing\n');
              for (final e in consumers) {
                b.writeln('  [ ] ${e.from} — ${e.fieldLevel ? "reads fields" : "confirm impact"}');
              }
              final reach = await _reach;
              if (reach != null && reach.transitive.isNotEmpty) {
                b.writeln('\nDownwind (only if the change is passed on):');
                for (final id in reach.transitive) {
                  b.writeln('  - $id');
                }
              }
              await Clipboard.setData(ClipboardData(text: b.toString()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Heads-up plan copied')));
              }
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

/// LAYERS is a real filter, not a label: on a hundred-node estate hiding the layers you are not
/// working in is the difference between a map and a wall.
class _LayersMenu extends StatelessWidget {
  final Set<String> hidden;
  final ValueChanged<String> onToggle;
  const _LayersMenu({required this.hidden, required this.onToggle});

  static const _itemHeight = 38.0;
  // Flutter does not clamp a popup vertically — it will happily lay the menu off the bottom of the
  // window. The command bar is docked near the bottom, so open upward, sized from the real item
  // count rather than a magic number so adding a layer cannot push it off-screen again.
  static double get _liftAboveBar =>
      _Layout.layers.length * _itemHeight + 16 /* list padding */ + 10 /* gap */;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Show or hide API-led layers',
      position: PopupMenuPosition.over,
      offset: Offset(0, -_liftAboveBar),
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        side: const BorderSide(color: AppColors.hairlineStrong),
      ),
      onSelected: onToggle,
      itemBuilder: (context) => [
        for (final layer in _Layout.layers)
          PopupMenuItem(
            value: layer,
            height: _itemHeight,
            child: Row(children: [
              Icon(
                hidden.contains(layer) ? Icons.check_box_outline_blank : Icons.check_box,
                size: 16,
                color: hidden.contains(layer) ? AppColors.textGhost : AppColors.forLayer(layer),
              ),
              const SizedBox(width: 10),
              Text(AppColors.layerBand(layer),
                  style: monoData(
                      size: 11,
                      color: hidden.contains(layer) ? AppColors.textMuted : AppColors.text)),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Text(
          hidden.isEmpty ? 'LAYERS' : 'LAYERS · ${_Layout.layers.length - hidden.length}',
          style: monoData(
              size: 11, color: hidden.isEmpty ? AppColors.textMuted : AppColors.accentSoft),
        ),
      ),
    );
  }
}
