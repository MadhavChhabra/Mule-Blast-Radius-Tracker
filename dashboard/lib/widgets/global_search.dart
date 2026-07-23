import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import 'skeleton.dart';

class SearchSelection {
  final String api;
  final String? endpoint;
  final String? field;
  const SearchSelection({required this.api, this.endpoint, this.field});
}

Future<SearchSelection?> showGlobalSearch(BuildContext context, ApiClient api) {
  return showDialog<SearchSelection>(
    context: context,
    builder: (_) => _GlobalSearchDialog(api: api),
  );
}

class _GlobalSearchDialog extends StatefulWidget {
  final ApiClient api;
  const _GlobalSearchDialog({required this.api});

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  Timer? _debounce;
  Future<SearchResults>? _results;
  String _q = '';
  int _focus = 0;
  List<SearchSelection> _flat = const [];
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _q = v.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () => _load(_q));
  }

  void _load(String q) {
    if (!mounted) return;
    setState(() {
      _results = widget.api.search(q);
      _focus = 0;
      _flat = const [];
      _rowKeys.clear();
    });
  }

  void _rebuildFlat(SearchResults r) {
    final all = <SearchSelection>[
      for (final a in r.apis) SearchSelection(api: a.api),
      for (final e in r.endpoints) SearchSelection(api: e.api, endpoint: e.endpoint),
      for (final f in r.fields) SearchSelection(api: f.api, endpoint: f.endpoint, field: f.field),
    ];
    _flat = all;
    if (_focus >= _flat.length) _focus = _flat.isEmpty ? 0 : _flat.length - 1;
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_flat.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _focus = (_focus + 1) % _flat.length);
      _scrollFocusIntoView();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _focus = (_focus - 1 + _flat.length) % _flat.length);
      _scrollFocusIntoView();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      Navigator.of(context).pop(_flat[_focus]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _scrollFocusIntoView() {
    final key = _rowKeys[_focus];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 120),
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    hintText: 'Search APIs, endpoints, fields…',
                  ),
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) {
                    if (_flat.isNotEmpty) Navigator.of(context).pop(_flat[_focus]);
                  },
                ),
              ),
              const Divider(height: 1),
              Flexible(child: _resultBody(context)),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      'Selecting an endpoint or field opens the API hub focused on it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  _kbdHint('↑↓'),
                  const SizedBox(width: 6),
                  _kbdHint('Enter'),
                  const SizedBox(width: 6),
                  _kbdHint('Esc'),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultBody(BuildContext context) {
    return FutureBuilder<SearchResults>(
      future: _results,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            child: Shimmer(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SkeletonBox(width: 90, height: 12),
                SizedBox(height: 10),
                SkeletonBox(height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 260, height: 14),
                SizedBox(height: 20),
                SkeletonBox(width: 90, height: 12),
                SizedBox(height: 10),
                SkeletonBox(height: 14),
              ]),
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(snap.error.toString().replaceFirst('Exception: ', '')),
          );
        }
        final r = snap.data ?? const SearchResults([], [], []);
        _rebuildFlat(r);
        if (r.isEmpty) {
          return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No matches.')));
        }
        int idx = 0;
        return ListView(
          controller: _scroll,
          shrinkWrap: true,
          children: [
            if (r.apis.isNotEmpty) ..._section(context, 'APIs & apps', [
              for (final a in r.apis) _row(idx++, Icons.api_outlined, a.api, null,
                  SearchSelection(api: a.api)),
            ]),
            if (r.endpoints.isNotEmpty) ..._section(context, 'Endpoints', [
              for (final e in r.endpoints) _row(idx++, Icons.route_outlined, e.endpoint, e.api,
                  SearchSelection(api: e.api, endpoint: e.endpoint), mono: true),
            ]),
            if (r.fields.isNotEmpty) ..._section(context, 'Fields', [
              for (final f in r.fields) _row(idx++, Icons.data_object_outlined, f.field,
                  '${f.api}  ·  ${f.endpoint}',
                  SearchSelection(api: f.api, endpoint: f.endpoint, field: f.field), mono: true),
            ]),
          ],
        );
      },
    );
  }

  Widget _row(int index, IconData icon, String title, String? subtitle,
      SearchSelection selection, {bool mono = false}) {
    final key = _rowKeys.putIfAbsent(index, () => GlobalKey());
    final focused = _focus == index;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: key,
      color: focused ? scheme.primary.withOpacity(0.10) : null,
      child: ListTile(
        dense: true,
        leading: Icon(icon, size: 20,
            color: focused ? scheme.primary : null),
        title: Text(title,
            style: TextStyle(
                fontFamily: mono ? 'monospace' : null,
                fontSize: mono ? 13 : null,
                fontWeight: focused ? FontWeight.w700 : null)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        trailing: focused ? Icon(Icons.keyboard_return, size: 16, color: scheme.primary) : null,
        onTap: () => Navigator.of(context).pop(selection),
        onFocusChange: (has) { if (has) setState(() => _focus = index); },
      ),
    );
  }

  Widget _kbdHint(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  List<Widget> _section(BuildContext context, String label, List<Widget> tiles) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        ...tiles,
      ];
}
