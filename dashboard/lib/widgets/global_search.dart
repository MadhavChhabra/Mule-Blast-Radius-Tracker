import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

Future<String?> showGlobalSearch(BuildContext context, ApiClient api) {
  return showDialog<String>(
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
  late Future<GraphDto> _graph;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _graph = widget.api.graph();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
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
                  hintText: 'Search APIs, apps, systems…',
                ),
                onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<GraphDto>(
                future: _graph,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                  }
                  final nodes = (snap.data?.nodes ?? [])
                      .where((n) => _q.isEmpty || n.label.toLowerCase().contains(_q) || n.id.toLowerCase().contains(_q))
                      .toList()
                    ..sort((a, b) => b.dependedOnBy.compareTo(a.dependedOnBy));
                  if (nodes.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No matches.')));
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: nodes.length,
                    itemBuilder: (context, i) {
                      final n = nodes[i];
                      final color = AppColors.forLayer(n.layer);
                      return ListTile(
                        leading: Container(width: 10, height: 10,
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        title: Text(n.label),
                        subtitle: Text(AppColors.layerLabel(n.layer),
                            style: TextStyle(color: color, fontSize: 12)),
                        trailing: Text('↓${n.dependsOn}  ↑${n.dependedOnBy}',
                            style: Theme.of(context).textTheme.bodySmall),
                        onTap: () => Navigator.of(context).pop(n.id),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Select to open in the Endpoint inspector', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
