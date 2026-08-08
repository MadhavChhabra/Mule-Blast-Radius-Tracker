import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

enum _Filter { all, breakingOnly, recent }

class ChangelogScreen extends StatefulWidget {
  final ApiClient api;
  const ChangelogScreen({super.key, required this.api});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  late Future<List<ChangelogEntry>> _future = widget.api.changelog();
  _Filter _filter = _Filter.all;

  void _reload() {
    final next = widget.api.changelog();
    setState(() => _future = next);
  }

  bool _matches(ChangelogEntry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.breakingOnly => e.markdown.toLowerCase().contains('breaking'),
        _Filter.recent => _within30Days(e.publishedAt),
      };

  static bool _within30Days(String? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso);
    if (t == null) return true;
    return DateTime.now().difference(t).inDays <= 30;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScreenHeader('Changelog', 'Written for you from each classified diff.'),
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 18),
          child: Row(children: [
            _pill('All APIs', _Filter.all),
            const SizedBox(width: 8),
            _pill('Breaking only', _Filter.breakingOnly),
            const SizedBox(width: 8),
            _pill('Last 30 days', _Filter.recent),
          ]),
        ),
        Expanded(
          child: AsyncView<List<ChangelogEntry>>(
            future: _future,
            onRetry: _reload,
            builder: (context, entries) {
              final shown = entries.where(_matches).toList();
              if (entries.isEmpty) {
                return const EmptyState(
                  icon: Icons.history_edu_outlined,
                  title: 'No changelog entries yet',
                  message: 'Check a change on any API and its changelog is written here '
                      'automatically — you never write one by hand.',
                );
              }
              if (shown.isEmpty) {
                return const EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: 'Nothing matches this filter',
                  message: 'No entry here fits the filter you picked. Switch back to All APIs '
                      'to see everything that has been recorded.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 32),
                itemCount: shown.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, i) => _ChangelogCard(shown[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pill(String label, _Filter f) {
    final on = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: on ? const Color(0x12FFFFFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: on ? Colors.transparent : AppColors.hairlineStrong),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11.5, color: on ? AppColors.text : AppColors.textMuted)),
      ),
    );
  }
}

/// One entry: a classification bar, the API and version, then mono-kicker sections with
/// em-dash bullets. Identifiers sit one step brighter than the body.
class _ChangelogCard extends StatelessWidget {
  final ChangelogEntry entry;
  const _ChangelogCard(this.entry);

  /// The generated Markdown is grouped under headings; render those as the design's kickers rather
  /// than as generic markdown. The document title and the version line are dropped — the card
  /// header already carries both, and repeating them was pure noise.
  static Map<String, List<String>> _sections(String markdown, String? api, String? version) {
    final out = <String, List<String>>{};
    String? current;
    for (final raw in markdown.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        final heading = line.replaceAll('#', '').trim();
        // Skip "# Changelog" and "# <api> 1.2.0" style titles.
        final lower = heading.toLowerCase();
        if (lower == 'changelog' ||
            (api != null && lower.contains(api.toLowerCase())) ||
            RegExp(r'^v?\d+\.\d+').hasMatch(heading)) {
          current = null;
          continue;
        }
        current = heading.toUpperCase();
        out.putIfAbsent(current, () => []);
        continue;
      }
      final body = (line.startsWith('-') || line.startsWith('*'))
          ? line.substring(1).trim()
          : line;
      // A bare version/summary line before the first heading is header material, not content.
      if (current == null) {
        final plain = _strip(body).toLowerCase();
        if (RegExp(r'^v?\d+\.\d+').hasMatch(plain)) continue;
        if (version != null && plain == version.toLowerCase()) continue;
        current = 'SUMMARY';
        out.putIfAbsent(current, () => []);
      }
      out.putIfAbsent(current, () => []).add(body);
    }
    return out;
  }

  static String _strip(String s) =>
      s.replaceAll('**', '').replaceAll('`', '').replaceAll('_', '').trim();

  static Color _kickerColor(String section) {
    final s = section.toLowerCase();
    if (s.contains('break')) return AppColors.breakingText;
    if (s.contains('add')) return AppColors.additive;
    if (s.contains('remov')) return AppColors.warning;
    return AppColors.textFaint;
  }

  static bool _isBreaking(String markdown) => markdown.toLowerCase().contains('breaking');

  @override
  Widget build(BuildContext context) {
    final sections = _sections(entry.markdown, entry.api, entry.versionLabel);
    return SolidPanel(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 2,
            height: 22,
            decoration: BoxDecoration(
              color: _isBreaking(entry.markdown) ? AppColors.breaking : AppColors.additive,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(entry.api ?? 'API',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              if (entry.versionLabel != null) ...[
                const SizedBox(width: 8),
                Text(entry.versionLabel!, style: monoData(size: 12)),
              ],
            ]),
          ),
          if (entry.publishedAt != null)
            Text(entry.publishedAt!.split('T').first, style: monoData(size: 10.5)),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: entry.markdown));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Changelog Markdown copied')));
            },
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.content_copy, size: 16, color: AppColors.textMuted),
            ),
          ),
        ]),
        for (final section in sections.entries) ...[
          const SizedBox(height: 14),
          Text(section.key, style: monoLabel(color: _kickerColor(section.key))),
          for (final line in section.value)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: _bullet(line),
            ),
        ],
      ]),
    );
  }

  static const _body = TextStyle(
      fontFamily: kSans, fontSize: 12.5, height: 1.7, color: AppColors.textSecondary);
  static const _code =
      TextStyle(fontFamily: kMono, fontSize: 11.5, height: 1.7, color: AppColors.text);
  static const _strong = TextStyle(
      fontFamily: kMono, fontSize: 11.5, height: 1.7, color: AppColors.text);
  static const _em = TextStyle(
      fontFamily: kSans,
      fontSize: 12.5,
      height: 1.7,
      fontStyle: FontStyle.italic,
      color: AppColors.textMuted);

  /// Renders the generated Markdown's inline marks — `code`, **strong**, _emphasis_ — instead of
  /// printing the asterisks and underscores verbatim.
  Widget _bullet(String line) {
    final spans = <TextSpan>[
      const TextSpan(text: '— ', style: _body),
    ];
    final pattern = RegExp(r'`([^`]+)`|\*\*([^*]+)\*\*|_([^_]+)_');
    int at = 0;
    for (final m in pattern.allMatches(line)) {
      if (m.start > at) {
        spans.add(TextSpan(text: line.substring(at, m.start), style: _body));
      }
      // The generator nests marks (**`GET /orders/{id}`**), so the captured text is cleaned of any
      // remaining inline syntax rather than printed with stray backticks or asterisks.
      if (m.group(1) != null) {
        spans.add(TextSpan(text: _strip(m.group(1)!), style: _code));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(text: _strip(m.group(2)!), style: _strong));
      } else {
        spans.add(TextSpan(text: _strip(m.group(3)!), style: _em));
      }
      at = m.end;
    }
    if (at < line.length) {
      spans.add(TextSpan(text: line.substring(at), style: _body));
    }
    return RichText(text: TextSpan(children: spans));
  }
}
