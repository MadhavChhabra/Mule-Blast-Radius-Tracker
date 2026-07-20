import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../util/file_upload.dart';
import '../widgets.dart';
import '../widgets/global_search.dart';
import '../widgets/impact_list.dart';
import '../widgets/skeleton.dart';

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
    final id = await showGlobalSearch(context, widget.api);
    if (id != null && mounted) setState(() => _api = id);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Endpoints'),
            Tab(text: 'Change impact'),
            Tab(text: 'Consumers & blast radius'),
            Tab(text: 'Spec & history'),
          ]),
          Expanded(
            child: _api == null
                ? const EmptyState(
                    icon: Icons.search,
                    title: 'Pick an API to inspect',
                    message: 'Use “Change API” above or the search palette (Ctrl/Cmd-K) to choose one.')
                : TabBarView(children: [
                    _EndpointsTab(api: widget.api, apiId: _api!, open: widget.open),
                    _ChangeImpactTab(api: widget.api, apiId: _api!),
                    _ConsumersTab(api: widget.api, apiId: _api!, graph: _graph!, open: widget.open),
                    _HistoryTab(api: widget.api, apiId: _api!),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Row(children: [
        Icon(Icons.api, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_api ?? 'API', style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
            Text('Everything about this API — relationships, change impact, consumers, history.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        OutlinedButton.icon(
          onPressed: _pickApi,
          icon: const Icon(Icons.search, size: 16),
          label: const Text('Change API'),
        ),
      ]),
    );
  }
}

class _EndpointsTab extends StatefulWidget {
  final ApiClient api;
  final String apiId;
  final OpenFn? open;
  const _EndpointsTab({required this.api, required this.apiId, this.open});

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
    return Column(children: [
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
      Expanded(
        child: _detail == null
            ? const SizedBox()
            : AsyncView<EndpointInspect>(future: _detail!, builder: (context, d) => _directions(context, d)),
      ),
    ]);
  }

  Widget _directions(BuildContext context, EndpointInspect d) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: _col(context, Icons.north_west, AppColors.experience, 'Called by (upstream)',
            d.calledBy.map((c) => _consumerRow(context, c.consumer, c.layer, c.viaEndpoint, c.fields)).toList(),
            'Nothing calls this endpoint (that we have scanned).')),
        const SizedBox(width: 16),
        Expanded(child: _col(context, Icons.south_east, AppColors.system, 'Calls (downstream)',
            [
              ...d.calls.map((p) => _producerRow(context, p.api, p.layer, p.endpoint, p.fields)),
              ...d.appLevelCalls.map((p) => _producerRow(context, p.api, p.layer, p.endpoint, p.fields)),
            ],
            'This endpoint calls nothing downstream.')),
      ]),
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

  void _run() {
    if (_spec.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _result = widget.api.propagate(api: widget.apiId, spec: _spec.text);
    });
    _result!.whenComplete(() => setState(() => _busy = false));
  }

  Future<void> _pickFile() async {
    final t = await pickTextFile();
    if (t != null) setState(() => _spec.text = t);
  }

  Future<void> _pickZip() async {
    final picked = await pickBinaryFile();
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final ex = await widget.api.extractSpecFromZip(picked.bytes, picked.name);
      if (mounted) {
        setState(() => _spec.text = ex.spec);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Zip: ${e.toString().replaceFirst('Exception: ', '')}')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

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
          ButtonSegment(value: 0, icon: Icon(Icons.account_tree_outlined, size: 16), label: Text('Field impact')),
          ButtonSegment(value: 1, icon: Icon(Icons.difference_outlined, size: 16), label: Text('Version diff')),
        ],
        selected: {_mode},
        onSelectionChanged: (s) => setState(() => _mode = s.first),
      ),
      const SizedBox(height: 12),
      if (_mode == 0) ..._propagationBody(context) else ..._versionDiffBody(context),
    ]);
  }

  List<Widget> _propagationBody(BuildContext context) => [
        Text('Paste this API\'s RAML/OpenAPI to see which field changes must be carried forward.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy ? null : _run,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.travel_explore),
            label: const Text('Scan fields'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _busy ? null : _pickZip,
              icon: const Icon(Icons.folder_zip_outlined, size: 16), label: const Text('RAML zip')),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _busy ? null : _pickFile,
              icon: const Icon(Icons.upload_file, size: 16), label: const Text('File')),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: TextField(
            controller: _spec,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                hintText: 'Paste RAML (#%RAML 1.0 …) or OpenAPI, or load a Design Center / Exchange asset'),
          ),
        ),
        const SizedBox(height: 12),
        if (_result != null)
          AsyncView<PropagationResult>(
              future: _result!, onRetry: _run, builder: (context, r) => _fields(context, r)),
      ];

  List<Widget> _versionDiffBody(BuildContext context) => [
        Text('Paste the before + after of this API\'s spec to detect breaking changes, the recommended '
            'version bump, deployment risk, impacted consumers and a generated changelog.',
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
          Expanded(child: _specBox('Before (baseline)', _oldSpec)),
          const SizedBox(width: 12),
          Expanded(child: _specBox('After (your change)', _newSpec)),
        ]),
        const SizedBox(height: 12),
        if (_analysis != null)
          AsyncView<AnalyzeResult>(
              future: _analysis!, onRetry: _analyze, builder: (context, r) => _diff(context, r)),
      ];

  Widget _specBox(String label, TextEditingController c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 4),
          SizedBox(
            height: 140,
            child: TextField(
              controller: c,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                  hintText: 'Paste RAML or OpenAPI'),
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
      Row(children: [
        _stat(context, 'Risk', '${r.advisory.riskLevel} · ${r.advisory.riskScore}/100', riskColor),
        const SizedBox(width: 10),
        _stat(context, 'Version', versionText, Theme.of(context).colorScheme.primary),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _stat(context, 'Breaking', '${r.summary.breaking}', AppColors.breaking),
        const SizedBox(width: 8),
        _stat(context, 'Safe', '${r.summary.safe}', AppColors.safe),
        const SizedBox(width: 8),
        _stat(context, 'Additive', '${r.summary.additive}', AppColors.additive),
      ]),
      if (r.summary.impactedConsumers > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${r.summary.impactedConsumers} downstream consumer(s) impacted',
              style: const TextStyle(color: AppColors.breaking, fontWeight: FontWeight.w700)),
        ),
      const SizedBox(height: 12),
      ImpactList(r.impacts),
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

  Widget _stat(BuildContext context, String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  Widget _fields(BuildContext context, PropagationResult r) {
    final shown = _onlyImpacted ? r.items.where((f) => f.consumerCount > 0).toList() : r.items;
    final risky = r.impactedFields > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (risky ? AppColors.breaking : AppColors.additive).withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          risky
              ? '${r.impactedFields} of ${r.fields} fields would need carry-forward across ${r.impactedConsumers} consumer(s).'
              : 'None of the ${r.fields} fields have a known downstream consumer.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
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
                  color: f.consumerCount > 0 ? AppColors.breaking : AppColors.additive, shape: BoxShape.circle)),
              title: Row(children: [
                Text(f.field, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Text(f.endpoint, style: TextStyle(fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              trailing: Text(f.consumerCount > 0 ? '${f.consumerCount} to carry' : 'safe',
                  style: TextStyle(color: f.consumerCount > 0 ? AppColors.breaking : AppColors.additive,
                      fontWeight: FontWeight.w700, fontSize: 12)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                ...f.downstream.map((c) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.south_east, size: 18, color: AppColors.breaking),
                      title: Text(c.consumer),
                      subtitle: Text([
                        if (c.ownerTeam != null) 'team ${c.ownerTeam}',
                        if (c.reviewers.isNotEmpty) 'reviewers ${c.reviewers.map((r) => r.replaceAll('gh:', '')).join(', ')}',
                        if (c.slackChannel != null) 'slack ${c.slackChannel}',
                      ].join('  ·  '), style: const TextStyle(fontSize: 11)),
                    )),
                if (f.downstream.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _plan(r.api, f)));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Carry-forward plan copied')));
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
    final b = StringBuffer('Carry-forward — $api ${f.endpoint} · field "${f.field}"\n');
    for (final c in f.downstream) {
      b.writeln('  [ ] ${c.consumer} — update to handle "${f.field}" '
          '(${[if (c.ownerTeam != null) 'team=${c.ownerTeam}', if (c.reviewers.isNotEmpty) 'reviewers=${c.reviewers.join(',')}'].join(' ')})');
    }
    return b.toString();
  }
}

class _ConsumersTab extends StatelessWidget {
  final ApiClient api;
  final String apiId;
  final Future<GraphDto> graph;
  final OpenFn? open;
  const _ConsumersTab({required this.api, required this.apiId, required this.graph, this.open});

  @override
  Widget build(BuildContext context) {
    return AsyncView<GraphDto>(
      future: graph,
      builder: (context, g) {
        final consumers = g.edges.where((e) => e.to == apiId).toList();
        final deps = g.edges.where((e) => e.from == apiId).toList();
        final breaking = consumers.where((e) => e.risk == 'breaking').length;
        return ListView(padding: const EdgeInsets.all(24), children: [
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
          ...consumers.map((e) => _edgeTile(context, e.from, e.risk, e.via)),
          const SizedBox(height: 16),
          _section(context, 'Depends on', deps.length),
          if (deps.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('No known dependencies.')),
          ...deps.map((e) => _edgeTile(context, e.to, e.risk, e.via)),
        ]);
      },
    );
  }

  Widget _section(BuildContext context, String t, int n) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text('$t  ($n)', style: const TextStyle(fontWeight: FontWeight.w800)),
      );

  Widget _edgeTile(BuildContext context, String name, String risk, List<String> via) => Card(
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
                if (risk == 'breaking') const Text('breaking', style: TextStyle(fontSize: 11, color: AppColors.breaking)),
                const Icon(Icons.chevron_right, size: 16),
              ]),
              ...via.map((v) => Padding(padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text(v, style: TextStyle(fontSize: 12, fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant)))),
            ]),
          ),
        ),
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
            return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
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
            return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
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
              decoration: BoxDecoration(color: AppColors.seed.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Text(f, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
            ),
        ]),
      );
}

Widget _empty(BuildContext context, String title, String sub) =>
    EmptyState(icon: Icons.travel_explore_outlined, title: title, message: sub);
