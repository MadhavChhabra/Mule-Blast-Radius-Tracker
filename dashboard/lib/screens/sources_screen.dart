import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../main.dart';
import '../theme.dart';
import '../widgets.dart';

class SourcesScreen extends StatefulWidget {
  final ApiClient api;
  final OpenFn? open;
  const SourcesScreen({super.key, required this.api, this.open});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  Future<SourcesStatus>? _status;
  final _repoCtrl = TextEditingController();
  bool _busy = false;
  SyncAllResult? _result;
  SyncProgress? _progress;
  Timer? _pollTimer;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _resumeIfSyncRunning();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _repoCtrl.dispose();
    super.dispose();
  }

  Future<void> _resumeIfSyncRunning() async {
    try {
      final p = await widget.api.syncStatus();
      if (mounted && p.isRunning) {
        setState(() {
          _busy = true;
          _progress = p;
        });
        _startPolling();
      }
    } catch (_) {}
  }

  void _reload() {
    final next = widget.api.sourcesStatus();
    setState(() {
      _status = next;
    });
  }

  Future<void> _addRepo() async {
    final url = _repoCtrl.text.trim();
    if (url.isEmpty) return;
    try {
      await widget.api.sourcesAddRepo(url);
      _repoCtrl.clear();
      _reload();
    } catch (e) {
      _snack('Could not add: ${_clean(e)}');
    }
  }

  Future<void> _removeRepo(String url) async {
    await widget.api.sourcesRemoveRepo(url);
    _reload();
  }

  Future<void> _connectAnypoint() async {
    final ok = await showDialog<bool>(
        context: context, builder: (_) => _AnypointDialog(api: widget.api));
    if (ok == true) _reload();
  }

  Future<void> _disconnectAnypoint() async {
    await widget.api.sourcesDisconnectAnypoint();
    _reload();
  }

  Future<void> _syncAll() async {
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
      _result = null;
      _progress = null;
    });
    try {
      final p = await widget.api.startSync();
      setState(() => _progress = p);
      _startPolling();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = true;
        _message = _clean(e);
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _cancelSync() async {
    try {
      final p = await widget.api.cancelSync();
      if (mounted) setState(() => _progress = p);

    } catch (_) {}
  }

  static String _elapsedLabel(Duration d) {
    final s = d.inSeconds;
    return s < 60 ? '${s}s' : '${s ~/ 60}m ${s % 60}s';
  }

  Future<void> _poll() async {
    final SyncProgress p;
    try {
      p = await widget.api.syncStatus();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (p.isRunning) {
      setState(() => _progress = p);
      return;
    }
    _pollTimer?.cancel();
    widget.api.invalidateGraph();
    setState(() {
      _busy = false;
      _progress = p;
      if (p.isFailed) {
        _error = true;
        _message = p.error ?? 'Sync failed.';
        _result = null;
      } else {
        _result = p.result;
        _error = p.result?.note != null;
        _message = p.result == null ? null : _summary(p.result!);
      }
    });
  }

  String _summary(SyncAllResult r) {
    final parts = <String>[];
    if (r.anypoint != null) {
      parts.add('${r.anypoint!.exchangeAssets} Exchange API(s), ${r.anypoint!.contracts} contract(s)');
    }
    parts.add('${r.totalApps} Mule app(s) from ${r.repos.length} repo(s)');
    return 'Synced: ${parts.join(' · ')}.${r.note != null ? '\n${r.note}' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader('Sources',
            'Connect your Anypoint org and your repos. Wakegraph reads real relationships from both.'),
        Expanded(
          child: AsyncView<SourcesStatus>(
            future: _status!,
            builder: (context, s) => ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _syncBar(context, s),
                const SizedBox(height: 16),
                _anypointCard(context, s),
                const SizedBox(height: 16),
                _reposCard(context, s),
                if (_result != null) ...[
                  const SizedBox(height: 16),
                  _resultsCard(context, _result!),
                ] else if (_busy && _progress != null && _progress!.repoResults.isNotEmpty) ...[
                  const SizedBox(height: 16),

                  _resultsCard(context,
                      SyncAllResult(false, null, _progress!.repoResults, 0, null)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _syncBar(BuildContext context, SourcesStatus s) {
    final ready = s.anypointConfigured || s.repos.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sync everything', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              ready
                  ? 'Pulls the Anypoint catalog + contracts and scans every registered repo into one estate map.'
                  : 'Connect Anypoint or add a repo below, then sync.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: TextStyle(
                  fontSize: 12, color: _error ? AppColors.breaking : AppColors.additive)),
            ],
            if (_busy && _progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: _progress!.reposTotal > 0
                      ? (_progress!.reposDone / _progress!.reposTotal).clamp(0.0, 1.0)
                      : null,
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    '${_progress!.phase ?? 'Syncing…'}'
                    '${_progress!.reposTotal > 0 ? '  ·  ${_progress!.reposDone} / ${_progress!.reposTotal} repos' : ''}'
                    '  ·  ${_elapsedLabel(_progress!.elapsed)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _cancelSync,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('Cancel'),
                ),
              ]),
            ],
          ]),
        ),
        const SizedBox(width: 16),
        FilledButton.icon(
          onPressed: (!ready || _busy) ? null : _syncAll,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
          label: const Text('Sync everything'),
        ),
        if (widget.open != null) ...[
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => widget.open!(Tabs.graph),
            icon: const Icon(Icons.hub_outlined, size: 16),
            label: const Text('View map'),
          ),
        ],
      ]),
    );
  }

  Widget _anypointCard(BuildContext context, SourcesStatus s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(s.anypointConfigured ? Icons.cloud_done_outlined : Icons.cloud_outlined,
                color: s.anypointConfigured ? AppColors.additive : null),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Anypoint Platform', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  s.anypointConfigured
                      ? 'Connected${s.anypointEnv != null && s.anypointEnv!.isNotEmpty ? ' · ${s.anypointEnv}' : ''} — Exchange catalog + API Manager contracts.'
                      : 'Connect a Connected App (read scopes) to pull the catalog + contracts.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _connectAnypoint,
              icon: Icon(s.anypointConfigured ? Icons.settings_outlined : Icons.link, size: 16),
              label: Text(s.anypointConfigured ? 'Reconnect' : 'Connect'),
            ),
            if (s.anypointConfigured)
              IconButton(
                tooltip: 'Disconnect',
                onPressed: _disconnectAnypoint,
                icon: const Icon(Icons.link_off, size: 18),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _reposCard(BuildContext context, SourcesStatus s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.folder_copy_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Repos', style: TextStyle(fontWeight: FontWeight.w800)),
                Text('A repo URL, a whole GitHub org / Bitbucket workspace URL, or a local path. '
                    'Org URLs expand to every repo on sync. Flows + property files give per-endpoint detail.',
                    style: TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _repoCtrl,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'https://github.com/my-org  or  https://github.com/org/mule-api.git   (private: https://token@github.com/...)',
                ),
                onSubmitted: (_) => _addRepo(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
                onPressed: _addRepo, icon: const Icon(Icons.add, size: 16), label: const Text('Add')),
          ]),
          const SizedBox(height: 12),
          if (s.repos.isEmpty)
            Text('No repos yet.', style: Theme.of(context).textTheme.bodySmall)
          else
            ...s.repos.map((url) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.source_outlined, size: 18),
                  title: Text(_redact(url), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  trailing: IconButton(
                    tooltip: 'Remove repo',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _removeRepo(url),
                  ),
                )),
        ]),
      ),
    );
  }

  Widget _resultsCard(BuildContext context, SyncAllResult r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Last sync', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (r.anypoint != null)
            Text('Anypoint: ${r.anypoint!.exchangeAssets} API(s), ${r.anypoint!.contracts} contract(s), '
                '${r.anypoint!.consumersIngested} consumer(s)'
                '${r.anypoint!.rateLimited ? '  ·  rate-limited' : ''}',
                style: const TextStyle(fontSize: 13)),
          ...r.repos.map((repo) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(repo.error == null ? Icons.check_circle_outline : Icons.error_outline,
                      size: 16, color: repo.error == null ? AppColors.additive : AppColors.breaking),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      repo.error == null
                          ? '${_redact(repo.url)} — ${repo.apps} app(s)${repo.appNames.isEmpty ? '' : ': ${repo.appNames.join(', ')}'}'
                          : '${_redact(repo.url)} — ${repo.error}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ]),
              )),
        ]),
      ),
    );
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  static String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
  static String _redact(String url) => url.replaceAll(RegExp(r'://[^@/]+@'), '://***@');
}

class _AnypointDialog extends StatefulWidget {
  final ApiClient api;
  const _AnypointDialog({required this.api});

  @override
  State<_AnypointDialog> createState() => _AnypointDialogState();
}

class _AnypointDialogState extends State<_AnypointDialog> {
  final _id = TextEditingController();
  final _secret = TextEditingController();
  final _org = TextEditingController();
  final _env = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    _org.dispose();
    _env.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty || _secret.text.trim().isEmpty) {
      setState(() => _error = 'Client ID and Secret are required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.sourcesConfigureAnypoint(
        clientId: _id.text.trim(),
        clientSecret: _secret.text.trim(),
        orgId: _org.text.trim(),
        environment: _env.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [Icon(Icons.link), SizedBox(width: 8), Text('Connect Anypoint')]),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Create a Connected App (app acts on its own behalf) with read scopes for Exchange Viewer '
            'and API Manager. The secret is held only in server memory — never persisted or echoed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(controller: _id, decoration: const InputDecoration(
              labelText: 'Client ID', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(
            controller: _secret,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Client Secret',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show secret' : 'Hide secret',
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _org, decoration: const InputDecoration(
                labelText: 'Org ID (optional)', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _env, decoration: const InputDecoration(
                labelText: 'Environment (optional)', border: OutlineInputBorder(), isDense: true))),
          ]),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.breaking, fontSize: 12)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Connect'),
        ),
      ],
    );
  }
}
