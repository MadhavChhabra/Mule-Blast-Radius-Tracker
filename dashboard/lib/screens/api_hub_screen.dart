import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api.dart';
import '../main.dart';
import '../pins.dart';
import '../theme.dart';
import '../util/file_upload.dart';
import '../widgets.dart';
import '../widgets/global_search.dart';
import '../widgets/hub_widgets.dart';
import '../widgets/impact_list.dart';
import '../widgets/skeleton.dart';
import '../widgets/spec_diff.dart';

class ApiHubScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn? open;
  final String? initialApi;
  const ApiHubScreen({super.key, required this.api, this.open, this.initialApi});

  @override
  State<ApiHubScreen> createState() => _ApiHubScreenState();
}

class _ApiHubScreenState extends State<ApiHubScreen> {
  String? _api;
  Future<GraphDto>? _graph;

  @override
  void initState() {
    super.initState();
    _graph = widget.api.graph();
    _api = widget.initialApi;
    if (_api == null) {
      _graph!.then((g) {
        final apis = g.nodes.where((n) => n.api).map((n) => n.id).toList()..sort();
        if (mounted && _api == null && apis.isNotEmpty) setState(() => _api = apis.first);
      });
    }
  }

  Future<void> _pickApi() async {
    final sel = await showGlobalSearch(context, widget.api);
    if (sel != null && mounted) setState(() => _api = sel.api);
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return EmptyState(
        icon: Icons.search,
        title: 'Pick an API to inspect',
        message: 'Use the search palette (Ctrl/Cmd-K) or click any node on the estate map.',
        action: FilledButton.icon(
          onPressed: _pickApi,
          icon: const Icon(Icons.search, size: 16),
          label: const Text('Choose an API'),
        ),
      );
    }
    // The lineage strip gives orientation in 212px, so the answer column never competes with a
    // second copy of the graph. Tabs are ordered by what a developer opens this screen to do.
    return DefaultTabController(
      length: 3,
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FutureBuilder<GraphDto>(
          future: _graph,
          builder: (context, snap) => snap.hasData
              ? LineageStrip(
                  apiId: _api!,
                  graph: snap.data!,
                  onOpen: (id) => setState(() => _api = id),
                  onBack: () => widget.open?.call(Tabs.estate),
                )
              : Container(width: 212, color: AppColors.bar),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(context),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Change impact'),
                  Tab(text: 'Relationships'),
                  Tab(text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(children: [
                _ChangeImpactTab(api: widget.api, apiId: _api!),
                _RelationshipsTab(
                    api: widget.api, apiId: _api!, graph: _graph!, open: widget.open),
                _HistoryTab(api: widget.api, apiId: _api!),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
      child: LayoutBuilder(builder: (context, c) {
        // Under ~700px the metadata line and the in-flight pill are the first things to go —
        // the API name and the controls always survive.
        final roomy = c.maxWidth > 700;
        return Row(children: [
          Flexible(
            child: Text(_api ?? 'API',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall),
          ),
          if (roomy) ...[
            const SizedBox(width: 12),
            FutureBuilder<GraphDto>(
              future: _graph,
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final broken = snap.data!.edges
                    .where((e) => e.to == _api && e.risk == 'breaking')
                    .length;
                if (broken == 0) return const SizedBox.shrink();
                return StatusPill('$broken BREAKING IN FLIGHT', AppColors.breakingText,
                    bordered: true);
              },
            ),
          ],
          const Spacer(),
          if (roomy)
            FutureBuilder<GraphDto>(
              future: _graph,
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final node = snap.data!.nodes.where((n) => n.id == _api).firstOrNull;
                if (node == null) return const SizedBox.shrink();
                return Text(
                    '${node.dependedOnBy} consumer${node.dependedOnBy == 1 ? "" : "s"} · '
                    '${node.dependsOn} dependenc${node.dependsOn == 1 ? "y" : "ies"}',
                    style: monoData(size: 11));
              },
            ),
          const SizedBox(width: 12),
          if (_api != null)
            AnimatedBuilder(
              animation: Pins.instance,
              builder: (context, _) {
                final pinned = Pins.instance.isPinned(_api!);
                return IconButton(
                  tooltip:
                      pinned ? 'Unpin this API' : 'Pin this API — it leads the search palette',
                  onPressed: () => Pins.instance.toggle(_api!),
                  icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 20,
                      color: pinned ? AppColors.accentSoft : AppColors.textMuted),
                );
              },
            ),
          if (_api != null && roomy) _AnypointLinksButton(api: widget.api, apiId: _api!),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pickApi,
            tooltip: 'Change API  (Ctrl/Cmd-K)',
            icon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
          ),
        ]);
      }),
    );
  }
}

class _AnypointLinksButton extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  const _AnypointLinksButton({required this.api, required this.apiId});

  @override
  State<_AnypointLinksButton> createState() => _AnypointLinksButtonState();
}

class _AnypointLinksButtonState extends State<_AnypointLinksButton> {
  Future<AnypointLinks>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.anypointLinks(api: widget.apiId);
  }

  @override
  void didUpdateWidget(covariant _AnypointLinksButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiId != widget.apiId) {
      _future = widget.api.anypointLinks(api: widget.apiId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AnypointLinks>(
      future: _future,
      builder: (context, snap) {
        final links = snap.data;
        if (links == null || links.isEmpty) return const SizedBox.shrink();
        return PopupMenuButton<String>(
          tooltip: 'Open in Anypoint',
          onSelected: openExternal,
          itemBuilder: (_) => [
            if (links.exchange != null)
              PopupMenuItem(value: links.exchange!, child: const _AnypointRow(
                  icon: Icons.storefront_outlined, label: 'Exchange')),
            if (links.apiManager != null)
              PopupMenuItem(value: links.apiManager!, child: const _AnypointRow(
                  icon: Icons.admin_panel_settings_outlined, label: 'API Manager')),
            if (links.designCenter != null)
              PopupMenuItem(value: links.designCenter!, child: const _AnypointRow(
                  icon: Icons.design_services_outlined, label: 'Design Center')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.open_in_new, size: 16),
              SizedBox(width: 6),
              Text('Anypoint ▾'),
            ]),
          ),
        );
      },
    );
  }
}

class _AnypointRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _AnypointRow({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16), const SizedBox(width: 8), Text(label),
      ]);
}

/// "What does this API talk to, and who talks to it" is one question, so per-endpoint traffic and
/// the API-level consumer list live on one surface instead of two tabs the user has to correlate.
class _RelationshipsTab extends StatelessWidget {
  final ApiClient api;
  final String apiId;
  final Future<GraphDto> graph;
  final OpenFn? open;
  const _RelationshipsTab(
      {required this.api, required this.apiId, required this.graph, this.open});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _EndpointsTab(api: api, apiId: apiId, open: open, embedded: true),
        const Divider(height: 32),
        _ConsumersTab(api: api, apiId: apiId, graph: graph, open: open, embedded: true),
      ],
    );
  }
}

class _EndpointsTab extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  final OpenFn? open;

  /// Rendered inside a scrolling parent, so it must size to its content instead of expanding.
  final bool embedded;
  const _EndpointsTab({required this.api, required this.apiId, this.open, this.embedded = false});

  @override
  State<_EndpointsTab> createState() => _EndpointsTabState();
}

class _EndpointsTabState extends State<_EndpointsTab> {
  List<String> _endpoints = [];
  String? _endpoint;
  bool _loading = true;
  Object? _error;
  Future<EndpointInspect>? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.api.inspectEndpoint(widget.apiId);
      if (!mounted) return;
      setState(() {
        _endpoints = d.endpoints;
        _loading = false;
        if (_endpoints.isNotEmpty) _select(_endpoints.first);
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  void _select(String e) {
    setState(() {
      _endpoint = e;
      _detail = widget.api.inspectEndpoint(widget.apiId, endpoint: e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList();
    if (_error != null) return ApiErrorState(error: _error!, onRetry: _load);
    if (_endpoints.isEmpty) {
      return _empty(context, 'No endpoints known for this API yet.',
          'Add its repo in Sources and Sync — flows + property files give per-endpoint detail.');
    }
    final detail = _detail == null
        ? const SizedBox()
        : AsyncView<EndpointInspect>(
            future: _detail!, builder: (context, d) => _directions(context, d));
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        child: Row(children: [
          const Text('Endpoint  '),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _endpoints.contains(_endpoint) ? _endpoint : null,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: _endpoints
                  .map((e) => DropdownMenuItem(
                      value: e,
                      child: Text(e == '*' ? 'whole API (all consumers)' : e,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: e == '*' ? null : 'monospace', fontSize: 13))))
                  .toList(),
              onChanged: (v) {
                if (v != null) _select(v);
              },
            ),
          ),
        ]),
      ),
      // The two direction columns are a stretched pair, so inside a scrolling page they need a
      // bounded height of their own rather than an Expanded that has nothing to expand into.
      if (widget.embedded) SizedBox(height: 420, child: detail) else Expanded(child: detail),
    ]);
  }

  Widget _directions(BuildContext context, EndpointInspect d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: LayoutBuilder(builder: (context, c) {
        final upstream = _col(context, Icons.north_west, AppColors.experience,
            'Called by (upstream)',
            d.calledBy
                .map((c) => _consumerRow(context, c.consumer, c.layer, c.viaEndpoint, c.fields))
                .toList(),
            'Nothing calls this endpoint (that we have scanned).');
        final downstream = _col(context, Icons.south_east, AppColors.system,
            'Calls (downstream)',
            [
              ...d.calls.map((p) => _producerRow(context, p.api, p.layer, p.endpoint, p.fields)),
              ...d.appLevelCalls
                  .map((p) => _producerRow(context, p.api, p.layer, p.endpoint, p.fields)),
            ],
            'This endpoint calls nothing downstream.');
        // Side by side is the point — but below ~620px the two columns squeeze the identifiers
        // into ellipses, so they stack instead.
        if (c.maxWidth < 620) {
          return Column(children: [
            SizedBox(height: 200, child: upstream),
            const SizedBox(height: 12),
            SizedBox(height: 200, child: downstream),
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: upstream),
          const SizedBox(width: 16),
          Expanded(child: downstream),
        ]);
      }),
    );
  }

  Widget _col(BuildContext context, IconData icon, Color color, String title, List<Widget> rows, String empty) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            const Spacer(),
            Text('${rows.length}', style: TextStyle(color: color)),
          ]),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(empty, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(10), children: rows),
        ),
      ]),
    );
  }

  Widget _producerRow(BuildContext context, String api, String layer, String endpoint, List<String> fields) {
    return _relRow(context, api, layer, endpoint.trim().isEmpty || endpoint.trim() == '*' ? null : endpoint, fields,
        () => widget.open?.call(Tabs.apiHub, api: api));
  }

  Widget _consumerRow(BuildContext context, String consumer, String layer, String? via, List<String> fields) {
    return _relRow(context, consumer, layer, via == null ? null : 'via $via', fields,
        () => widget.open?.call(Tabs.apiHub, api: consumer));
  }

  Widget _relRow(BuildContext context, String name, String layer, String? sub, List<String> fields, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _LayerChip(layer: layer),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
              const Icon(Icons.chevron_right, size: 16),
            ]),
            if (sub != null)
              Padding(padding: const EdgeInsets.only(top: 3),
                  child: Text(sub, style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant))),
            if (fields.isNotEmpty) _FieldChips(fields: fields),
          ]),
        ),
      ),
    );
  }
}

class _ChangeImpactTab extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  const _ChangeImpactTab({required this.api, required this.apiId});

  @override
  State<_ChangeImpactTab> createState() => _ChangeImpactTabState();
}

class _ChangeImpactTabState extends State<_ChangeImpactTab> {
  int _mode = 0;
  final _spec = TextEditingController();
  Future<PropagationResult>? _result;
  final _oldSpec = TextEditingController();
  final _newSpec = TextEditingController();
  Future<AnalyzeResult>? _analysis;
  bool _busy = false;
  bool _onlyImpacted = true;
  LatestSpec? _latest;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    try {
      final l = await widget.api.latestSpec(widget.apiId);
      if (mounted) setState(() => _latest = l);
    } catch (_) {}
  }

  String get _baselineLabel {
    final l = _latest;
    if (l == null) return '';
    final date = (l.savedAt != null && l.savedAt!.length >= 10) ? l.savedAt!.substring(0, 10) : '';
    final parts = [
      if (l.versionLabel != null && l.versionLabel!.isNotEmpty) l.versionLabel!,
      if (date.isNotEmpty) date,
    ];
    return parts.isEmpty ? 'last recorded version' : parts.join(' · ');
  }

  void _run() {
    if (_spec.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _result = widget.api.propagate(api: widget.apiId, spec: _spec.text);
    });
    _result!.whenComplete(() => setState(() => _busy = false));
  }

  Future<void> _loadFileInto(TextEditingController c) async {
    final t = await pickTextFile();
    if (t != null && mounted) setState(() => c.text = t);
  }

  Future<void> _loadZipInto(TextEditingController c) async {
    final picked = await pickBinaryFile();
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final ex = await widget.api.extractSpecFromZip(picked.bytes, picked.name);
      if (mounted) setState(() => c.text = ex.spec);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zip: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _loadBaselineInto(TextEditingController c) {
    final l = _latest;
    if (l != null) setState(() => c.text = l.spec);
  }

  Widget _loaderBtn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      );

  void _analyze() {
    if (_oldSpec.text.trim().isEmpty || _newSpec.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _analysis = widget.api.analyze(api: widget.apiId, oldSpec: _oldSpec.text, newSpec: _newSpec.text);
    });
    _analysis!.whenComplete(() => setState(() => _busy = false));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, icon: Icon(Icons.account_tree_outlined, size: 16), label: Text('Who reads a field')),
          ButtonSegment(value: 1, icon: Icon(Icons.difference_outlined, size: 16), label: Text('Check a change')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      const SizedBox(height: 12),
      if (_mode == 0) ..._propagationBody(context) else ..._versionDiffBody(context),
    ]);
  }

  List<Widget> _propagationBody(BuildContext context) => [
        Text('Paste this API\'s spec (RAML or OpenAPI) to see which fields other apps read — '
            'so before you touch a field, you know who feels it.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.travel_explore),
            label: const Text('Scan fields'),
          ),
          if (_latest != null)
            OutlinedButton.icon(onPressed: _busy ? null : () => _loadBaselineInto(_spec),
                icon: const Icon(Icons.history, size: 16),
                label: Text('Load recorded ($_baselineLabel)')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _loadZipInto(_spec),
              icon: const Icon(Icons.folder_zip_outlined, size: 16), label: const Text('RAML zip')),
          OutlinedButton.icon(onPressed: _busy ? null : () => _loadFileInto(_spec),
              icon: const Icon(Icons.upload_file, size: 16), label: const Text('File')),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 180,
          child: TextField(
            controller: _spec,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                hintText: 'Paste RAML (#%RAML 1.0 …) or OpenAPI, load a file/zip, or use the recorded version'),
          ),
        ),
        const SizedBox(height: 12),
        if (_result != null)
          AsyncView<PropagationResult>(
              future: _result!, onRetry: _run, builder: (context, r) => _fields(context, r)),
      ];

  List<Widget> _versionDiffBody(BuildContext context) => [
        Text('Paste the before and after of this API\'s spec. You\'ll get: what breaks, how to ship it '
            'safely, the version bump to use, the deployment risk, who\'s affected, and a ready changelog.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy ? null : _analyze,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.play_arrow),
          label: const Text('Analyze'),
        ),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _specBox('Before (baseline)', _oldSpec, baseline: true)),
          const SizedBox(width: 12),
          Expanded(child: _specBox('After (your change)', _newSpec)),
        ]),
        const SizedBox(height: 12),
        if (_analysis != null)
          AsyncView<AnalyzeResult>(
              future: _analysis!, onRetry: _analyze, builder: (context, r) => _diff(context, r)),
      ];

  Widget _specBox(String label, TextEditingController c, {bool baseline = false}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
            if (baseline && _latest != null)
              _loaderBtn(Icons.history, 'Load recorded version ($_baselineLabel)',
                  _busy ? null : () => _loadBaselineInto(c)),
            _loaderBtn(Icons.folder_zip_outlined, 'Load a RAML zip', _busy ? null : () => _loadZipInto(c)),
            _loaderBtn(Icons.upload_file, 'Load a spec file', _busy ? null : () => _loadFileInto(c)),
          ]),
          const SizedBox(height: 4),
          SizedBox(
            height: 200,
            child: TextField(
              controller: c,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                  hintText: 'Paste RAML or OpenAPI, or use the icons above'),
            ),
          ),
        ],
      );

  Widget _diff(BuildContext context, AnalyzeResult r) {
    final riskColor = switch (r.advisory.riskLevel) {
      'CRITICAL' || 'HIGH' => AppColors.breaking,
      'MEDIUM' => AppColors.safe,
      'LOW' => AppColors.additive,
      _ => AppColors.neutral,
    };
    final versionText = r.advisory.recommendedBump == 'NONE'
        ? 'No version bump needed'
        : (r.advisory.currentVersion != null && r.advisory.nextVersion != null
            ? '${r.advisory.recommendedBump} · ${r.advisory.currentVersion} → ${r.advisory.nextVersion}'
            : r.advisory.recommendedBump);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      VerdictCard(result: r, riskColor: riskColor, versionText: versionText),
      const SizedBox(height: 16),
      ImpactList(r.impacts),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: const Icon(Icons.difference_outlined, size: 20),
            title: const Text('Spec diff', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('See exactly what changed, line by line',
                style: Theme.of(context).textTheme.bodySmall),
            children: [
              SpecDiffView(oldText: _oldSpec.text, newText: _newSpec.text),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Generated changelog', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy Markdown',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.changelog));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Changelog copied')));
                },
              ),
            ]),
            const Divider(),
            MarkdownBody(data: r.changelog, selectable: true),
          ]),
        ),
      ),
    ]);
  }

  Widget _fields(BuildContext context, PropagationResult r) {
    final shown = _onlyImpacted ? r.items.where((f) => f.consumerCount > 0).toList() : r.items;
    final confirmed = r.confirmedFields;
    final risky = confirmed > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (risky ? AppColors.breaking : AppColors.additive).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          risky
              ? '$confirmed of ${r.fields} fields have a proven reader — changing those ripples out.'
              : 'No app is known to read any of these ${r.fields} fields.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      if (r.unknownConsumers > 0) ...[
        const SizedBox(height: 8),
        _UnknownFieldDataNote(consumers: r.unknownConsumers),
      ],
      Row(children: [
        const Spacer(),
        const Text('Only impacted', style: TextStyle(fontSize: 12)),
        Switch(value: _onlyImpacted, onChanged: (v) => setState(() => _onlyImpacted = v)),
      ]),
      if (shown.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No impacted fields.')),
      ...shown.map((f) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ExpansionTile(
              leading: Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: f.confirmedCount > 0
                      ? AppColors.breaking
                      : (f.unknownCount > 0 ? AppColors.warning : AppColors.additive),
                  shape: BoxShape.circle)),
              title: Row(children: [
                Text(f.field, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Tooltip(
                  message: f.isRequest ? 'Request field — callers send it' : 'Response field — consumers read it',
                  child: Icon(f.isRequest ? Icons.north_east : Icons.south_west,
                      size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(f.endpoint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ),
              ]),
              trailing: _FieldVerdict(field: f),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                ...f.downstream.map((c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          f.isRequest
                              ? Icons.north_east
                              : (c.fieldConfirmed ? Icons.south_east : Icons.help_outline),
                          size: 18,
                          color: f.isRequest || c.fieldConfirmed
                              ? AppColors.breaking
                              : AppColors.warning),
                      title: Text(c.consumer),
                      subtitle: Text([
                        if (f.isRequest)
                          'calls this endpoint — must send this field'
                        else
                          c.fieldConfirmed
                              ? 'reads this field'
                              : 'no field-level data — may or may not read it',
                        if (c.ownerTeam != null) 'team ${c.ownerTeam}',
                        if (c.reviewers.isNotEmpty) 'reviewers ${c.reviewers.map((r) => r.replaceAll('gh:', '')).join(', ')}',
                      ].join('  ·  '), style: const TextStyle(fontSize: 11)),
                      trailing: _ConsumerActions(consumer: c),
                    )),
                if (f.downstream.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _plan(r.api, f)));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Heads-up plan copied')));
                      },
                      icon: const Icon(Icons.checklist_rtl, size: 16),
                      label: const Text('Copy plan'),
                    ),
                  ),
              ],
            ),
          )),
    ]);
  }

  String _plan(String api, PropagationField f) {
    String who(ConsumerDto c) => [
          if (c.ownerTeam != null) 'team=${c.ownerTeam}',
          if (c.reviewers.isNotEmpty) 'reviewers=${c.reviewers.join(',')}',
        ].join(' ');
    final b = StringBuffer('Before changing "${f.field}" — $api ${f.endpoint}\n');
    if (f.isRequest) {
      b.writeln('Request field — every caller of this endpoint has to send it:');
      for (final c in f.downstream) {
        b.writeln('  [ ] ${c.consumer} — update the request it sends (${who(c)})');
      }
      return b.toString();
    }
    final confirmed = f.downstream.where((c) => c.fieldConfirmed);
    final unknown = f.downstream.where((c) => !c.fieldConfirmed);
    if (confirmed.isNotEmpty) {
      b.writeln('Reads this field — give them a heads-up:');
      for (final c in confirmed) {
        b.writeln('  [ ] ${c.consumer} — update to handle "${f.field}" (${who(c)})');
      }
    }
    if (unknown.isNotEmpty) {
      b.writeln('Consumes this API, no field-level data — confirm with them:');
      for (final c in unknown) {
        b.writeln('  [ ] ${c.consumer} — does it read "${f.field}"? (${who(c)})');
      }
    }
    return b.toString();
  }
}

/// Knowing who to tell is only half the job — these turn the owner metadata into the message.
class _ConsumerActions extends StatelessWidget {
  final ConsumerDto consumer;
  const _ConsumerActions({required this.consumer});

  @override
  Widget build(BuildContext context) {
    final slack = consumer.slackChannel;
    final reviewers = consumer.reviewers.map((r) => '@${r.replaceAll('gh:', '')}').toList();
    if (slack == null && reviewers.isEmpty && consumer.sourceRepo == null) {
      return const SizedBox.shrink();
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (slack != null)
        IconButton(
          tooltip: 'Open $slack in Slack',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.forum_outlined, size: 17),
          onPressed: () => openExternal(
              'https://slack.com/app_redirect?channel=${Uri.encodeComponent(slack.replaceFirst('#', ''))}'),
        ),
      if (reviewers.isNotEmpty)
        IconButton(
          tooltip: 'Copy reviewer mentions (${reviewers.join(' ')})',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.alternate_email, size: 17),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: reviewers.join(' ')));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Reviewer mentions copied')));
          },
        ),
      if (consumer.sourceRepo != null)
        IconButton(
          tooltip: 'Open ${consumer.sourceRepo}',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.open_in_new, size: 17),
          onPressed: () => openExternal(consumer.sourceRepo!.startsWith('http')
              ? consumer.sourceRepo!
              : 'https://github.com/${consumer.sourceRepo}'),
        ),
    ]);
  }
}

/// The verdict a developer acts on: a proven reader is a blocker, a consumer with no field-level
/// data is a question to ask, and neither is safe to show as the same number.
class _FieldVerdict extends StatelessWidget {
  final PropagationField field;
  const _FieldVerdict({required this.field});

  @override
  Widget build(BuildContext context) {
    if (field.consumerCount == 0) {
      return const Text('safe',
          style: TextStyle(color: AppColors.additive, fontWeight: FontWeight.w700, fontSize: 12));
    }
    if (field.isRequest) {
      // Nobody can prove who sends a field, but everyone who calls the endpoint has to change.
      return Tooltip(
        message: 'Callers of this endpoint build the request, so a new or changed required field '
            'affects all of them.',
        child: Text('${field.consumerCount} must send it',
            style: const TextStyle(
                color: AppColors.breaking, fontWeight: FontWeight.w700, fontSize: 12)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (field.confirmedCount > 0)
        Text('${field.confirmedCount} read it',
            style: const TextStyle(
                color: AppColors.breaking, fontWeight: FontWeight.w700, fontSize: 12)),
      if (field.confirmedCount > 0 && field.unknownCount > 0)
        Text('  ·  ',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      if (field.unknownCount > 0)
        Tooltip(
          message: 'Consumers of this API with no field-level data. Register their repos to '
              'turn this into a yes or no.',
          child: Text('${field.unknownCount} unknown',
              style: const TextStyle(
                  color: AppColors.warning, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
    ]);
  }
}

class _UnknownFieldDataNote extends StatelessWidget {
  final int consumers;
  const _UnknownFieldDataNote({required this.consumers});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.help_outline, size: 18, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$consumers consumer(s) have no field-level data — they were found through an Anypoint '
            'contract or a flow with no DataWeave, so every field counts as "maybe". Register their '
            'repos in Sources to replace the guess with an answer.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

class _ConsumersTab extends StatelessWidget {
  final ApiClient api;
  final String apiId;
  final Future<GraphDto> graph;
  final OpenFn? open;
  final bool embedded;
  const _ConsumersTab({required this.api, required this.apiId, required this.graph, this.open,
      this.embedded = false});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([graph, api.manifests()]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: SkeletonList(rows: 3));
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(snap.error.toString().replaceFirst('Exception: ', '')),
          );
        }
        final g = snap.data![0] as GraphDto;
        final manifests = snap.data![1] as List<ManifestDto>;
        final byConsumer = <String, ManifestDto>{
          for (final m in manifests) m.consumer.toLowerCase(): m,
        };
        final consumers = g.edges.where((e) => e.to == apiId).toList();
        final deps = g.edges.where((e) => e.from == apiId).toList();
        final breaking = consumers.where((e) => e.risk == 'breaking').length;
        return ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: embedded,
            physics: embedded ? const NeverScrollableScrollPhysics() : null,
            children: [
          if (breaking > 0)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.breaking.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.breaking, size: 18),
                const SizedBox(width: 8),
                Text('$breaking consumer(s) hit by a recent breaking change',
                    style: const TextStyle(color: AppColors.breaking, fontWeight: FontWeight.w700)),
              ]),
            ),
          _GovernanceCard(api: api, apiId: apiId),
          _section(context, 'Consumed by (blast radius)', consumers.length),
          if (consumers.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No known consumers.')),
          ...consumers.map((e) => _edgeTile(context, e.from, e.risk, e.via,
              byConsumer[e.from.toLowerCase()])),
          const SizedBox(height: 16),
          _section(context, 'Depends on', deps.length),
          if (deps.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No known dependencies.')),
          ...deps.map((e) => _edgeTile(context, e.to, e.risk, e.via, null)),
        ]);
      },
    );
  }

  Widget _section(BuildContext context, String t, int n) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$t  ($n)', style: const TextStyle(fontWeight: FontWeight.w800)),
      );

  Widget _edgeTile(BuildContext context, String name, String risk, List<String> via,
      ManifestDto? manifest) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () => open?.call(Tabs.apiHub, api: name),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: AppColors.forRisk(risk), shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (risk == 'breaking') const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Text('breaking', style: TextStyle(fontSize: 11, color: AppColors.breaking))),
                const Icon(Icons.chevron_right, size: 16),
              ]),
              if (manifest != null) _readinessChips(context, manifest),
              ...via.map((v) => Padding(padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(v, style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant)))),
            ]),
          ),
        ),
      );

  Widget _readinessChips(BuildContext context, ManifestDto m) {
    final chips = <Widget>[];
    if (m.discoveredOnly) {
      chips.add(_chip(context, Icons.travel_explore, 'discovered — no manifest committed',
          AppColors.warning));
    } else if (m.ownerTeam != null && m.ownerTeam!.isNotEmpty) {
      chips.add(_chip(context, Icons.groups_outlined, 'team ${m.ownerTeam}', AppColors.additive));
    }
    if (m.updatedAt != null && m.updatedAt!.isNotEmpty) {
      final day = m.updatedAt!.length >= 10 ? m.updatedAt!.substring(0, 10) : m.updatedAt!;
      chips.add(_chip(context, Icons.schedule_outlined, 'last seen $day', AppColors.neutral));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 16),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          border: Border.all(color: color.withOpacity(0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _GovernanceCard extends StatelessWidget {
  final ApiClient api;
  final String apiId;
  const _GovernanceCard({required this.api, required this.apiId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InsightFinding>>(
      future: api.insights(),
      builder: (context, snap) {
        final findings = (snap.data ?? const <InsightFinding>[])
            .where((f) => f.apis.contains(apiId))
            .toList();
        if (findings.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.policy_outlined, size: 18),
              const SizedBox(width: 8),
              Text('Governance findings involving this API (${findings.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            const SizedBox(height: 8),
            ...findings.map((f) {
              final c = f.severity == 'high'
                  ? AppColors.breaking
                  : (f.severity == 'medium' ? AppColors.warning : AppColors.neutral);
              return Tooltip(
                message: f.detail,
                waitDuration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(width: 8, height: 8,
                          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.title, style: const TextStyle(fontSize: 12.5))),
                  ]),
                ),
              );
            }),
          ]),
        );
      },
    );
  }
}

class _HistoryTab extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  const _HistoryTab({required this.api, required this.apiId});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  late Future<List<ChangeDto>> _changes;
  late Future<List<ChangelogEntry>> _changelog;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _changes = widget.api.changes(widget.apiId);
    _changelog = widget.api.changelog(api: widget.apiId);
  }

  void _reload() => setState(_load);

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Recent changes', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      FutureBuilder<List<ChangeDto>>(
        future: _changes,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Shimmer(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 10),
                  SkeletonBox(height: 10),
                  SizedBox(height: 8),
                  SkeletonBox(width: 300, height: 10),
                ]),
              ),
            );
          }
          if (snap.hasError) return _InlineError(error: snap.error!, onRetry: _reload);
          final changes = snap.data ?? [];
          if (changes.isEmpty) return const Text('No recorded changes for this API yet.');
          return Column(children: changes.take(50).map((c) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: RiskChip(c.classification),
                title: Text(c.description ?? c.kind, style: const TextStyle(fontSize: 13)),
                subtitle: c.endpoint == null ? null : Text(c.endpoint!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              )).toList());
        },
      ),
      const Divider(height: 32),
      const Text('Changelog', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      FutureBuilder<List<ChangelogEntry>>(
        future: _changelog,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Shimmer(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SkeletonBox(width: 220, height: 14),
                  SizedBox(height: 10),
                  SkeletonBox(height: 10),
                  SizedBox(height: 8),
                  SkeletonBox(width: 300, height: 10),
                ]),
              ),
            );
          }
          if (snap.hasError) return _InlineError(error: snap.error!, onRetry: _reload);
          final entries = snap.data ?? [];
          if (entries.isEmpty) return const Text('No changelog yet — run a change impact analysis.');
          return Column(children: entries.map((e) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: MarkdownBody(data: e.markdown, selectable: true),
                ),
              )).toList());
        },
      ),
    ]);
  }
}

class _InlineError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _InlineError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final info = describeApiError(error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(info.icon, size: 16, color: info.color),
        const SizedBox(width: 8),
        Expanded(child: Text(info.detail, style: Theme.of(context).textTheme.bodySmall)),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 14),
          label: const Text('Retry'),
        ),
      ]),
    );
  }
}

class _LayerChip extends StatelessWidget {
  final String layer;
  const _LayerChip({required this.layer});
  @override
  Widget build(BuildContext context) {
    final color = AppColors.forLayer(layer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
      child: Text(AppColors.layerLabel(layer),
          style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10)),
    );
  }
}

class _FieldChips extends StatelessWidget {
  final List<String> fields;
  const _FieldChips({required this.fields});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in fields)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(f, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
        ]),
      );
}

Widget _empty(BuildContext context, String title, String sub) =>
    EmptyState(icon: Icons.travel_explore_outlined, title: title, message: sub);
