import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../api.dart';
import '../widgets.dart';

class ChangelogScreen extends StatefulWidget {
  final ApiClient api;
  const ChangelogScreen({super.key, required this.api});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late Future<List<ChangelogEntry>> _future = widget.api.changelog();

  void _reload() {
    final next = widget.api.changelog();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader('Changelog', 'Generated automatically from each classified diff.'),
        Expanded(
          child: AsyncView<List<ChangelogEntry>>(
            future: _future,
            onRetry: _reload,
            builder: (context, entries) {
              if (entries.isEmpty) {
                return const EmptyState(
                  icon: Icons.history_edu_outlined,
                  title: 'No changelog entries yet',
                  message: 'Run a change-impact analysis on an API to generate its changelog.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(24),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, i) => _ChangelogCard(entries[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ChangelogCard extends StatelessWidget {
  final ChangelogEntry entry;
  const _ChangelogCard(this.entry);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tag, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text('${entry.api ?? ''}  ${entry.versionLabel ?? ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (entry.publishedAt != null)
                  Text(entry.publishedAt!.split('T').first,
                      style: Theme.of(context).textTheme.bodySmall),
                IconButton(
                  tooltip: 'Copy Markdown',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.markdown));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Changelog Markdown copied')));
                  },
                ),
              ],
            ),
            const Divider(),
            MarkdownBody(data: entry.markdown, selectable: true),
          ],
        ),
      ),
    );
  }
}
