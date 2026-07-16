import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/sources_screen.dart';
import 'screens/graph_screen.dart';
import 'screens/api_hub_screen.dart';
import 'screens/changelog_screen.dart';
import 'theme.dart';
import 'util/file_upload.dart' as web_util;
import 'widgets/global_search.dart';

void main() => runApp(const ApiGuardApp());

class Tabs {
  static const home = 0;
  static const sources = 1;
  static const graph = 2;
  static const apiHub = 3;
  static const changelog = 4;

  static const discover = sources;
  static const impact = apiHub;
  static const propagation = apiHub;
  static const explorer = apiHub;
  static const endpoint = apiHub;
  static const radar = graph;
  static const changes = apiHub;
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
      title: 'Wakegraph',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
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

  static const _tabNames = ['home', 'sources', 'graph', 'hub', 'changelog'];

  bool _searchOpen = false;

  bool _handleKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyK &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
      if (!_searchOpen) _search();
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
    final idx = _tabNames.indexOf(parts[0]);
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
        title: const Text('Server access'),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('If the Wakegraph server has API-key auth enabled '
                '(apiguard.security.api-key), paste the key here. It is stored only in this '
                'browser.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                labelText: 'API key (leave empty for open servers)',
              ),
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
      if (result != null) _open(Tabs.apiHub, api: result);
    } finally {
      _searchOpen = false;
    }
  }

  late final List<_NavItem> _items = [
    _NavItem('Home', Icons.home_outlined, (a, open, t) => HomeScreen(api: a, open: open)),
    _NavItem('Sources', Icons.cable_outlined, (a, open, t) => SourcesScreen(api: a, open: open)),
    _NavItem('Estate map', Icons.hub_outlined, (a, open, t) => GraphScreen(api: a, open: open)),
    _NavItem('API', Icons.api_outlined, (a, open, t) => ApiHubScreen(
        key: ValueKey('hub:${t?.api}'), api: a, open: open, initialApi: t?.api)),
    _NavItem('Changelog', Icons.history_edu_outlined, (a, open, t) => ChangelogScreen(api: a)),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [

          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _go,
                    labelType: NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        children: [
                          Icon(Icons.shield_outlined, color: scheme.primary, size: 30),
                          const SizedBox(height: 4),
                          Text('Wakegraph',
                              style: TextStyle(fontWeight: FontWeight.w800, color: scheme.primary)),
                          const SizedBox(height: 12),
                          IconButton.filledTonal(
                            onPressed: _search,
                            icon: const Icon(Icons.search, size: 20),
                            tooltip: 'Search APIs (Ctrl/Cmd-K)',
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(height: 4),
                          IconButton(
                            onPressed: _serverKeyDialog,
                            icon: Icon(Icons.key_outlined, size: 18,
                                color: ApiClient.apiKey == null ? null : scheme.primary),
                            tooltip: 'Server access (API key)',
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    destinations: _items
                        .map((it) => NavigationRailDestination(
                            icon: Icon(it.icon), label: Text(it.label)))
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _animatedPage(context)),
        ],
      ),
    );
  }

  Widget _animatedPage(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetKey = _index == Tabs.apiHub ? (_target?.api ?? '') : '';
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: SizedBox.expand(
        key: ValueKey('page:$_index:$targetKey'),
        child: _items[_index].build(api, _open, _target),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  final Widget Function(ApiClient api, OpenFn open, NavTarget? target) build;
  _NavItem(this.label, this.icon, this.build);
}
