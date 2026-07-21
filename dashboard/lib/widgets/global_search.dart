import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _results = widget.api.search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _q = v.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      setState(() => _results = widget.api.search(_q));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
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
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<SearchResults>(
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
                  if (r.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: Text('No matches.')));
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      if (r.apis.isNotEmpty) ..._section(context, 'APIs & apps', [
                        for (final a in r.apis)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.api_outlined, size: 20),
                            title: Text(a.api),
                            onTap: () => Navigator.of(context).pop(
                                SearchSelection(api: a.api)),
                          ),
                      ]),
                      if (r.endpoints.isNotEmpty) ..._section(context, 'Endpoints', [
                        for (final e in r.endpoints)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.route_outlined, size: 20),
                            title: Text(e.endpoint,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                            subtitle: Text(e.api,
                                style: TextStyle(fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            onTap: () => Navigator.of(context).pop(
                                SearchSelection(api: e.api, endpoint: e.endpoint)),
                          ),
                      ]),
                      if (r.fields.isNotEmpty) ..._section(context, 'Fields', [
                        for (final f in r.fields)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.data_object_outlined, size: 20),
                            title: Text(f.field,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                            subtitle: Text('${f.api}  ·  ${f.endpoint}',
                                style: TextStyle(fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            onTap: () => Navigator.of(context).pop(
                                SearchSelection(api: f.api, endpoint: f.endpoint, field: f.field)),
                          ),
                      ]),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('Selecting an endpoint or field opens the API hub focused on it.',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

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
