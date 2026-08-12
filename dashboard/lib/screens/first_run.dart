import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';

/// First run (2e): the empty estate with a docked three-step card. The logic here — Anypoint
/// connect, repo add, local-workspace candidates, sync polling — carries over unchanged; only the
/// surface it sits on has changed.
class FirstRunWizard extends StatefulWidget {
  final ApiClient api;
  final OpenFn open;
  final VoidCallback onDone;
  const FirstRunWizard(
      {super.key, required this.api, required this.open, required this.onDone});

  @override
  State<FirstRunWizard> createState() => FirstRunWizardState();
}

class FirstRunWizardState extends State<FirstRunWizard> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  final _orgId = TextEditingController();
  final _env = TextEditingController();
  final _repoUrl = TextEditingController();

  final List<String> _repos = [];
  final List<LocalCandidate> _localCandidates = [];
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
      final local = await widget.api.localCandidates();
      if (!mounted) return;
      setState(() {
        _localCandidates
          ..clear()
          ..addAll(local.where((c) => !s.repos.contains(c.path)));
        _anypointConfigured = s.anypointConfigured;
        _anypointOrgLabel = _formatOrg(s.anypointOrg, s.anypointEnv);
        _repos.clear();
        _repos.addAll(s.repos);
        _step = _anypointConfigured || _repos.isNotEmpty ? 1 : 0;
        if (_repos.isNotEmpty) _step = 2;
      });
    } catch (e) {
      // Silence here presented a pristine step-one wizard to a user whose server was simply
      // unreachable, inviting them to re-enter a configuration that was never lost.
      if (mounted) setState(() => _error = _clean(e));
    }
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

  Future<void> _addLocal(String path) async {
    setState(() { _busy = true; _error = null; });
    try {
      final s = await widget.api.sourcesAddRepo(path);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _repos
          ..clear()
          ..addAll(s.repos);
        _localCandidates.removeWhere((c) => c.path == path);
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
    // The headline lives on the canvas behind this card, so the card carries only the step rail
    // and the step you are on.
    return GlassPanel(
      strong: true,
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        _StepRail(step: _step, anypointDone: _anypointConfigured, reposDone: _repos.isNotEmpty),
        const SizedBox(height: 20),
        if (_error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.breaking.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadius.field),
              border: Border.all(color: AppColors.breaking.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: AppColors.breaking, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12.5))),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: SingleChildScrollView(child: _stepBody(context)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          TextButton.icon(
            onPressed: () => widget.open(Tabs.sources),
            icon: const Icon(Icons.settings_outlined, size: 15),
            label: const Text('Skip — I’ll do this in Sources'),
          ),
        ]),
      ]),
    );
  }

  Widget _stepBody(BuildContext context) => switch (_step) {
        0 => _stepContent(context, _anypointStep(context)),
        1 => _stepContent(context, _reposStep(context)),
        _ => _stepContent(context, _syncStep(context)),
      };

  Widget _stepContent(BuildContext context, Step step) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DefaultTextStyle(
          style: Theme.of(context).textTheme.titleMedium!,
          child: step.title,
        ),
        const SizedBox(height: 10),
        step.content,
      ]);

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
            '(optionally Exchange: Read). The secret is encrypted and saved, so you connect once.'),
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
        if (_localCandidates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.additive.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.additive.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.folder_special_outlined, size: 18, color: AppColors.additive),
                const SizedBox(width: 8),
                Text('Mule projects already on this machine',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _localCandidates)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 15),
                    label: Text('${c.name} · ${c.projects} project(s)'),
                    tooltip: c.path,
                    onPressed: _busy ? null : () => _addLocal(c.path),
                  ),
              ]),
            ]),
          ),
        ],
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
        const Text('BlipRadius reads your Anypoint contracts and scans every registered repo '
            'for its Mule flows, property files and DataWeave lineage. First sync on a real org '
            'is typically 1–2 minutes.'),
        // Someone who already had a repo registered lands straight on this step, so name what is
        // about to be read rather than asking them to take it on trust.
        if (_repos.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('WILL SCAN', style: monoLabel()),
          const SizedBox(height: 7),
          for (final r in _repos.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                const Icon(Icons.source_outlined, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoData(size: 11)),
                ),
              ]),
            ),
          if (_repos.length > 4)
            Text('+${_repos.length - 4} more', style: monoData(size: 11)),
        ],
        if (_anypointConfigured) ...[
          const SizedBox(height: 6),
          Row(children: [
            const Icon(Icons.cloud_done_outlined, size: 14, color: AppColors.additive),
            const SizedBox(width: 8),
            Text(_anypointOrgLabel ?? 'Anypoint connected', style: monoData(size: 11)),
          ]),
        ],
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


/// The three-step rail: done is an additive circle with a check, current is the accent circle
/// carrying its number, upcoming is an outline.
class _StepRail extends StatelessWidget {
  final int step;
  final bool anypointDone;
  final bool reposDone;
  const _StepRail({required this.step, required this.anypointDone, required this.reposDone});

  @override
  Widget build(BuildContext context) {
    Widget node(int i, String label, bool done) {
      final current = i == step;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: done
                ? AppColors.additive
                : (current ? AppColors.accent : Colors.transparent),
            borderRadius: BorderRadius.circular(11),
            border: done || current
                ? null
                : Border.all(color: AppColors.hairlineStrong),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, size: 14, color: AppColors.canvas)
                : Text('${i + 1}',
                    style: TextStyle(
                      fontFamily: kMono,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: current ? AppColors.canvas : AppColors.textFaint,
                    )),
          ),
        ),
        const SizedBox(width: 9),
        Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: current || done ? FontWeight.w500 : FontWeight.w400,
              color: current || done ? AppColors.text : AppColors.textMuted,
            )),
      ]);
    }

    Widget connector(bool lit) => Expanded(
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: lit ? AppColors.additive.withOpacity(0.4) : AppColors.hairlineStrong,
          ),
        );

    return Row(children: [
      node(0, 'Anypoint', anypointDone),
      connector(anypointDone),
      node(1, 'Repos', reposDone),
      connector(reposDone),
      node(2, 'Sync', false),
    ]);
  }
}
