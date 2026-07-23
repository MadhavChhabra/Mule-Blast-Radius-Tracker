import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../util/file_upload.dart' as web_util;
import '../widgets.dart';
import '../widgets/global_search.dart';
import '../widgets/skeleton.dart';

class HomeScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn open;
  const HomeScreen({super.key, required this.api, required this.open});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Key _wizardKey = UniqueKey();

  ApiClient get api => widget.api;
  OpenFn get open => widget.open;

  void _onWizardDone() {
    api.invalidateGraph();
    setState(() => _wizardKey = UniqueKey());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<GraphDto>(
      key: _wizardKey,
      future: api.graph(),
      builder: (context, snap) {
        final loading = snap.connectionState != ConnectionState.done;
        final empty = !loading && !snap.hasError && (snap.data?.nodes.isEmpty ?? true);
        if (empty) {
          return _FirstRunWizard(api: api, open: open, onDone: _onWizardDone);
        }
        return _buildDashboard(context, scheme);
      },
    );
  }

  Widget _buildDashboard(BuildContext context, ColorScheme scheme) {
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
              onPressed: () => showGlobalSearch(context, api).then((sel) {
                if (sel != null) open(Tabs.apiHub, api: sel.api, endpoint: sel.endpoint, field: sel.field);
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

class _FirstRunWizard extends StatefulWidget {
  final ApiClient api;
  final OpenFn open;
  final VoidCallback onDone;
  const _FirstRunWizard({required this.api, required this.open, required this.onDone});

  @override
  State<_FirstRunWizard> createState() => _FirstRunWizardState();
}

class _FirstRunWizardState extends State<_FirstRunWizard> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _orgId = TextEditingController();
  final _env = TextEditingController();
  final _repoUrl = TextEditingController();

  final List<String> _repos = [];
  bool _anypointConfigured = false;
  String? _anypointOrgLabel;
  int _step = 0;
  bool _busy = false;
  String? _error;
  SyncProgress? _progress;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _prime();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clientId.dispose();
    _clientSecret.dispose();
    _orgId.dispose();
    _env.dispose();
    _repoUrl.dispose();
    super.dispose();
  }

  Future<void> _prime() async {
    try {
      final s = await widget.api.sourcesStatus();
      if (!mounted) return;
      setState(() {
        _anypointConfigured = s.anypointConfigured;
        _anypointOrgLabel = _formatOrg(s.anypointOrg, s.anypointEnv);
        _repos.clear();
        _repos.addAll(s.repos);
        _step = _anypointConfigured || _repos.isNotEmpty ? 1 : 0;
        if (_repos.isNotEmpty) _step = 2;
      });
    } catch (_) {}
  }

  static String? _formatOrg(String? org, String? env) {
    if (org == null && env == null) return null;
    if (org != null && env != null) return '$org · $env';
    return org ?? env;
  }

  Future<void> _saveAnypoint() async {
    if (_clientId.text.trim().isEmpty || _clientSecret.text.trim().isEmpty) {
      setState(() => _error = 'Client ID and secret are required.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final s = await widget.api.sourcesConfigureAnypoint(
        clientId: _clientId.text.trim(),
        clientSecret: _clientSecret.text.trim(),
        orgId: _orgId.text.trim().isEmpty ? null : _orgId.text.trim(),
        environment: _env.text.trim().isEmpty ? null : _env.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _anypointConfigured = s.anypointConfigured;
        _anypointOrgLabel = _formatOrg(s.anypointOrg, s.anypointEnv);
        _clientSecret.clear();
        _step = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = _clean(e); });
    }
  }

  Future<void> _addRepo() async {
    final url = _repoUrl.text.trim();
    if (url.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final s = await widget.api.sourcesAddRepo(url);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _repos
          ..clear()
          ..addAll(s.repos);
        _repoUrl.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = _clean(e); });
    }
  }

  Future<void> _startSync() async {
    setState(() { _busy = true; _error = null; _progress = null; });
    try {
      final p = await widget.api.startSync();
      if (!mounted) return;
      setState(() => _progress = p);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollSync());
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = _clean(e); });
    }
  }

  Future<void> _pollSync() async {
    try {
      final p = await widget.api.syncStatus();
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.isDone || p.isFailed) {
        _pollTimer?.cancel();
        _busy = false;
        if (p.isDone) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) widget.onDone();
        }
      }
    } catch (_) {}
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

  bool get _canGoStep1 => _anypointConfigured || _repos.isNotEmpty;
  bool get _canSync => _anypointConfigured || _repos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            Row(children: [
              Icon(Icons.shield_outlined, size: 34, color: scheme.primary),
              const SizedBox(width: 12),
              Text('Welcome to Wakegraph',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
            ]),
            const SizedBox(height: 6),
            Text('Three quick steps to see your MuleSoft estate. This is minimum-setup, '
                'not a one-way door — you can change anything later from Sources.',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            if (_error != null)
              Card(
                color: AppColors.breaking.withOpacity(0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: AppColors.breaking, size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                  ]),
                ),
              ),
            Card(
              child: Stepper(
                currentStep: _step,
                controlsBuilder: (_, __) => const SizedBox.shrink(),
                onStepTapped: (i) {
                  if (i == 2 && !_canSync) return;
                  setState(() => _step = i);
                },
                steps: [
                  _anypointStep(context),
                  _reposStep(context),
                  _syncStep(context),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => widget.open(Tabs.sources),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: const Text('Skip the wizard — go to Sources'),
            ),
          ],
        ),
      ),
    );
  }

  Step _anypointStep(BuildContext context) {
    final done = _anypointConfigured;
    return Step(
      state: done ? StepState.complete : (_step == 0 ? StepState.editing : StepState.indexed),
      isActive: _step >= 0,
      title: Row(children: [
        const Text('Connect Anypoint', style: TextStyle(fontWeight: FontWeight.w700)),
        if (done) ...[
          const SizedBox(width: 8),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text(_anypointOrgLabel ?? 'connected'),
            avatar: const Icon(Icons.check_circle, size: 16, color: AppColors.additive),
          ),
        ],
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paste a Connected App credential with API Manager: Read '
            '(optionally Exchange: Read). Secrets are stored in memory only.'),
        const SizedBox(height: 12),
        TextField(
          controller: _clientId,
          enabled: !_busy,
          decoration: const InputDecoration(
              isDense: true, border: OutlineInputBorder(), labelText: 'Client ID'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _clientSecret,
          enabled: !_busy,
          obscureText: true,
          decoration: const InputDecoration(
              isDense: true, border: OutlineInputBorder(), labelText: 'Client Secret'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: _orgId,
            enabled: !_busy,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder(),
                labelText: 'Org ID (optional)'),
          )),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            controller: _env,
            enabled: !_busy,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder(),
                labelText: 'Environment (optional)'),
          )),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy ? null : _saveAnypoint,
            icon: const Icon(Icons.link, size: 18),
            label: Text(done ? 'Update' : 'Connect'),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step = 1),
            child: const Text('Skip for now'),
          ),
        ]),
      ]),
    );
  }

  Step _reposStep(BuildContext context) {
    final done = _repos.isNotEmpty;
    return Step(
      state: done
          ? StepState.complete
          : (_step == 1 ? StepState.editing : StepState.indexed),
      isActive: _step >= 1,
      title: Row(children: [
        const Text('Add your repos', style: TextStyle(fontWeight: FontWeight.w700)),
        if (done) ...[
          const SizedBox(width: 8),
          Chip(
            visualDensity: VisualDensity.compact,
            label: Text('${_repos.length} added'),
            avatar: const Icon(Icons.check_circle, size: 16, color: AppColors.additive),
          ),
        ],
      ]),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paste a GitHub/Bitbucket repo URL, or an org URL — orgs expand to '
            'every repo they own. You can add more than one.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(
            controller: _repoUrl,
            enabled: !_busy,
            decoration: const InputDecoration(
                isDense: true, border: OutlineInputBorder(),
                hintText: 'https://github.com/your-org  or  https://github.com/your-org/orders-exp-api'),
            onSubmitted: (_) => _addRepo(),
          )),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _addRepo,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
          ),
        ]),
        if (_repos.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final r in _repos)
              Chip(
                label: Text(r, style: const TextStyle(fontSize: 12)),
                avatar: const Icon(Icons.source_outlined, size: 14),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        Row(children: [
          FilledButton.icon(
            onPressed: _busy || !_canGoStep1 ? null : () => setState(() => _step = 2),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Continue'),
          ),
        ]),
      ]),
    );
  }

  Step _syncStep(BuildContext context) {
    final p = _progress;
    final running = p?.isRunning == true;
    final done = p?.isDone == true;
    final failed = p?.isFailed == true;
    return Step(
      state: done
          ? StepState.complete
          : failed
              ? StepState.error
              : (_step == 2 ? StepState.editing : StepState.indexed),
      isActive: _step >= 2,
      title: const Text('Sync everything', style: TextStyle(fontWeight: FontWeight.w700)),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Wakegraph reads your Anypoint contracts and scans every registered repo '
            'for its Mule flows, property files and DataWeave lineage. First sync on a real org '
            'is typically 1–2 minutes.'),
        const SizedBox(height: 14),
        if (!running && !done && !failed)
          FilledButton.icon(
            onPressed: _canSync && !_busy ? _startSync : null,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Sync everything'),
          ),
        if (running) ...[
          LinearProgressIndicator(
            value: (p!.reposTotal == 0) ? null : p.reposDone / p.reposTotal,
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Text('${p.phase ?? "Running…"}   '
              '${p.reposTotal == 0 ? "" : "${p.reposDone}/${p.reposTotal} repos"}',
              style: Theme.of(context).textTheme.bodySmall),
        ],
        if (done)
          const Row(children: [
            Icon(Icons.check_circle, color: AppColors.additive),
            SizedBox(width: 8),
            Text('Sync complete. Loading your estate…'),
          ]),
        if (failed)
          Row(children: [
            const Icon(Icons.error_outline, color: AppColors.breaking),
            const SizedBox(width: 8),
            Expanded(child: Text(p?.error ?? 'Sync failed.',
                style: const TextStyle(color: AppColors.breaking))),
          ]),
      ]),
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
          return const _HealthShell(child: Padding(
            padding: EdgeInsets.all(16),
            child: Shimmer(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 140, height: 16),
                SizedBox(height: 16),
                Row(children: [
                  SkeletonBox(width: 120, height: 56, radius: 12),
                  SizedBox(width: 10),
                  SkeletonBox(width: 120, height: 56, radius: 12),
                  SizedBox(width: 10),
                  SkeletonBox(width: 120, height: 56, radius: 12),
                ]),
              ]),
            ),
          ));
        }
        if (snap.hasError) {
          final info = describeApiError(snap.error!);
          return _HealthShell(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(info.icon, color: info.color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(info.title, style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(info.detail, style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
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
              const Text('Add a Mule repo or connect Anypoint, then Sync — that builds the map.'),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.icon(onPressed: () => open(Tabs.sources),
                    icon: const Icon(Icons.cable_outlined, size: 18), label: const Text('Connect a source')),
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
        builder: (context) => Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Container(
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
