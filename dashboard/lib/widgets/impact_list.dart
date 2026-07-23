import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

class ImpactList extends StatelessWidget {
  final List<Impact> impacts;
  const ImpactList(this.impacts, {super.key});

  @override
  Widget build(BuildContext context) {
    if (impacts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('No changes detected.')),
      );
    }
    return Column(
      children: impacts.map((i) => _ImpactCard(i)).toList(),
    );
  }
}

class _ImpactCard extends StatelessWidget {
  final Impact impact;
  const _ImpactCard(this.impact);

  @override
  Widget build(BuildContext context) {
    final c = impact.change;
    final breaking = c.classification == 'BREAKING';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RiskChip(c.classification),
                const SizedBox(width: 10),
                if (c.endpoint != null)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(c.endpoint!,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(c.description ?? c.kind),
            if (breaking && c.remediation != null && c.remediation!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.additive.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.additive.withOpacity(0.30)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.health_and_safety_outlined, size: 16, color: AppColors.additive),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodySmall,
                        children: [
                          const TextSpan(
                              text: 'Ship it safely  ',
                              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.additive)),
                          TextSpan(
                              text: c.remediation!,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ],
            if (impact.downstream.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.south_east, size: 15,
                    color: breaking ? AppColors.breaking : AppColors.neutral),
                const SizedBox(width: 6),
                Text(breaking
                    ? '${impact.downstream.length} consumer(s) may break'
                    : '${impact.downstream.length} consumer(s) depend on this',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: breaking ? AppColors.breaking : Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 4),
              ...impact.downstream.map((d) => Padding(
                    padding: const EdgeInsets.only(left: 21, top: 2),
                    child: Text(
                        '• ${d.consumer}'
                        '${d.ownerTeam != null && d.ownerTeam != '?' ? '  ·  team ${d.ownerTeam}' : ''}'
                        '${d.reviewers.isNotEmpty ? '  ·  reviewers ${d.reviewers.map((r) => r.replaceAll('gh:', '')).join(', ')}' : ''}'
                        '${d.slackChannel != null ? '  ·  ${d.slackChannel}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                  )),
            ],
            if (impact.upstream.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.north_west, size: 15, color: AppColors.neutral),
                const SizedBox(width: 6),
                Text('sourced from', style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
              ]),
              ...impact.upstream.map((u) => Padding(
                    padding: const EdgeInsets.only(left: 21, top: 2),
                    child: Text('• ${u.api}  ${u.endpoint}.${u.field}',
                        style: Theme.of(context).textTheme.bodySmall),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
