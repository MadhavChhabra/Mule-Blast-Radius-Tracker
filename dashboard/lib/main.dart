import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'pins.dart';
import 'screens/sources_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/api_hub_screen.dart';
import 'screens/changelog_screen.dart';
import 'theme.dart';
import 'util/file_upload.dart' as web_util;
import 'widgets/global_search.dart';
import 'widgets/shortcuts_help.dart';

void main() => runApp(const ApiGuardApp());

/// Four surfaces, not five: the comp makes the estate map the home surface, so what used to be a
/// separate dashboard now docks onto the canvas as panels.
class Tabs {
  static const estate = 0;
  static const apiHub = 1;
  static const changelog = 2;
  static const sources = 3;

  /// Kept so existing cross-navigation keeps compiling and routing sensibly.
  static const home = estate;
  static const graph = estate;
}

class NavTarget {
  final String? api;
  final String? endpoint;
  final String? field;
  const NavTarget({this.api, this.endpoint, this.field});
}

typedef OpenFn = void Function(int index, {String? api, String? endpoint, String? field});

class ApiGuardApp extends StatelessWidget {
  const ApiGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlipRadius',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final api = ApiClient();
  int _index = 0;
  NavTarget? _target;
  bool _searchOpen = false;

  static const _tabNames = ['estate', 'hub', 'changelog', 'sources'];
  static const _labels = ['Estate', 'API hub', 'Changelog', 'Sources'];

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final ctrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (event.logicalKey == LogicalKeyboardKey.keyK && ctrlOrCmd) {
      if (!_searchOpen) _search();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.slash && ctrlOrCmd) {
      showShortcutsHelp(context);
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    ApiClient.apiKey = web_util.loadStoredApiKey();

    final initial = _parseHash(web_util.readLocationHash());
    if (initial != null) {
      _index = initial.$1;
      _target = initial.$2;
    }
    web_util.onHashChange((hash) {
      final parsed = _parseHash(hash);
      if (parsed != null && mounted) {
        setState(() {
          _index = parsed.$1;
          _target = parsed.$2;
        });
      }
    });
  }

  static (int, NavTarget?)? _parseHash(String hash) {
    final h = hash.startsWith('#') ? hash.substring(1) : hash;
    final parts = h.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    // Older links used /home and /graph; both now land on the estate canvas.
    final name = switch (parts[0]) { 'home' || 'graph' => 'estate', final v => v };
    final idx = _tabNames.indexOf(name);
    if (idx < 0) return null;
    final target = parts.length > 1 && idx == Tabs.apiHub
        ? NavTarget(api: Uri.decodeComponent(parts[1]))
        : null;
    return (idx, target);
  }

  void _writeHash() {
    final api = _index == Tabs.apiHub ? _target?.api : null;
    web_util.writeLocationHash(
        '#/${_tabNames[_index]}${api == null ? '' : '/${Uri.encodeComponent(api)}'}');
  }

  void _go(int index) {
    setState(() {
      _index = index;
      _target = null;
    });
    _writeHash();
  }

  void _open(int index, {String? api, String? endpoint, String? field}) {
    setState(() {
      _index = index;
      _target = NavTarget(api: api, endpoint: endpoint, field: field);
    });
    _writeHash();
  }

  Future<void> _serverKeyDialog() async {
    final ctrl = TextEditingController(text: ApiClient.apiKey ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: const BorderSide(color: AppColors.hairlineStrong),
        ),
        title: const Text('Server access'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('If this BlipRadius server has API-key auth enabled, paste the key here. '
                'It is stored only in this browser.'),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'API key'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      final v = ctrl.text.trim();
      ApiClient.apiKey = v.isEmpty ? null : v;
      web_util.storeApiKey(v.isEmpty ? null : v);
      api.invalidateGraph();
      if (mounted) setState(() {});
    }
    ctrl.dispose();
  }

  Future<void> _search() async {
    _searchOpen = true;
    try {
      final result = await showGlobalSearch(context, api);
      if (result != null) {
        _open(Tabs.apiHub, api: result.api, endpoint: result.endpoint, field: result.field);
      }
    } finally {
      _searchOpen = false;
    }
  }

  Widget _page() {
    switch (_index) {
      case Tabs.apiHub:
        return ApiHubScreen(
            key: ValueKey('hub:${_target?.api}'),
            api: api,
            open: _open,
            initialApi: _target?.api);
      case Tabs.changelog:
        return ChangelogScreen(api: api);
      case Tabs.sources:
        return SourcesScreen(api: api, open: _open);
      default:
        return GraphScreen(api: api, open: _open);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onCanvas = _index == Tabs.estate;
    return Scaffold(
      backgroundColor: onCanvas ? AppColors.canvas : AppColors.shell,
      body: Stack(children: [
        // The estate canvas runs full-bleed under its floating bar; framed surfaces sit below a
        // solid one, so the bar is part of the page rather than hovering over content.
        Positioned.fill(
          top: onCanvas ? 0 : 52,
          child: _page(),
        ),
        if (onCanvas)
          Positioned(
            left: 28,
            right: 28,
            top: 24,
            // The brief is explicit: in focus mode the top bar *becomes* the focus bar. Drawing a
            // second bar under this one just hid it.
            child: AnimatedBuilder(
              animation: FocusState.instance,
              builder: (context, _) => FocusState.instance.active
                  ? FocusBar(
                      api: FocusState.instance.api!,
                      hops: FocusState.instance.hops,
                      nodes: FocusState.instance.nodes,
                      direction: FocusDirection.values[FocusState.instance.direction],
                      onDirection: (d) => FocusState.instance.onDirection?.call(d.index),
                      onClose: () => FocusState.instance.onClose?.call(),
                      onHub: () => FocusState.instance.onOpenHub?.call(),
                    )
                  : _TopBar(
                      index: _index,
                      labels: _labels,
                      onSelect: _go,
                      onSearch: _search,
                      onKey: _serverKeyDialog,
                      floating: true,
                      api: api,
                    ),
            ),
          )
        else
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _TopBar(
              index: _index,
              labels: _labels,
              onSelect: _go,
              onSearch: _search,
              onKey: _serverKeyDialog,
              floating: false,
              api: api,
            ),
          ),
      ]),
    );
  }
}

/// The comp's chrome: one bar, two renditions. Floating glass over the estate; a solid ruled bar
/// on the framed surfaces.
class _TopBar extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onKey;
  final bool floating;
  final ApiClient api;

  const _TopBar({
    required this.index,
    required this.labels,
    required this.onSelect,
    required this.onSearch,
    required this.onKey,
    required this.floating,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(children: [
      const BrandMark(size: 22),
      const SizedBox(width: 9),
      const Text('BlipRadius',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
      const SizedBox(width: 16),
      Container(width: 1, height: 20, color: AppColors.hairlineStrong),
      const SizedBox(width: 16),
      for (int i = 0; i < labels.length; i++) ...[
        _NavPill(label: labels[i], selected: i == index, onTap: () => onSelect(i)),
        const SizedBox(width: 6),
      ],
      const Spacer(),
      _SyncStatus(api: api),
      const SizedBox(width: 14),
      _BarIcon(icon: Icons.search, tooltip: 'Search  Ctrl/Cmd-K', onTap: onSearch),
      _BarIcon(
        icon: Icons.vpn_key_outlined,
        tooltip: 'Server access (API key)',
        onTap: onKey,
        active: ApiClient.apiKey != null,
      ),
      _BarIcon(
          icon: Icons.keyboard_alt_outlined,
          tooltip: 'Keyboard shortcuts  Ctrl/Cmd-/',
          onTap: () => showShortcutsHelp(context)),
      const SizedBox(width: 10),
      FilledButton.icon(
        onPressed: () => onSelect(Tabs.apiHub),
        icon: const Icon(Icons.bolt, size: 16),
        label: const Text('Check a change'),
      ),
    ]);

    if (!floating) {
      return Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: const BoxDecoration(
          color: AppColors.bar,
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: content,
      );
    }
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      radius: AppRadius.panel,
      child: SizedBox(height: 52 - 2, child: content),
    );
  }
}

class _NavPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0x12FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: selected ? AppColors.text : AppColors.textMuted,
            )),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  const _BarIcon(
      {required this.icon, required this.tooltip, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon,
                size: 17, color: active ? AppColors.accentSoft : AppColors.textMuted),
          ),
        ),
      );
}

/// The comp's live pulse: a blinking dot and the age of the last sync.
class _SyncStatus extends StatefulWidget {
  final ApiClient api;
  const _SyncStatus({required this.api});

  @override
  State<_SyncStatus> createState() => _SyncStatusState();
}

class _SyncStatusState extends State<_SyncStatus> with SingleTickerProviderStateMixin {
  HealthInfo? _health;
  bool _error = false;
  Timer? _timer;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void initState() {
    super.initState();
    _check();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final h = await widget.api.health();
      if (mounted) setState(() { _health = h; _error = false; });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final up = _health != null && _health!.up && !_error;
    final color = _error ? AppColors.breaking : (up ? AppColors.additive : AppColors.textFaint);
    final label = _error ? 'OFFLINE' : (up ? 'CONNECTED · v${_health!.version}' : 'CHECKING…');
    return Tooltip(
      message: _error
          ? 'The BlipRadius server is unreachable'
          : 'BlipRadius server ${_health?.version ?? ""}',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        FadeTransition(
          opacity: Tween<double>(begin: 1, end: 0.25).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: monoData(size: 10.5, color: AppColors.textFaint)),
      ]),
    );
  }
}
