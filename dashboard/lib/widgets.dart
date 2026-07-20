import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets/skeleton.dart';

class AsyncView<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;
  final Widget? loading;
  const AsyncView(
      {super.key, required this.future, required this.builder, this.onRetry, this.loading});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return loading ?? const SkeletonList();
        }
        if (snap.hasError) {
          return ApiErrorState(error: snap.error!, onRetry: onRetry);
        }
        return builder(context, snap.data as T);
      },
    );
  }
}

/// What kind of failure an API call hit, so the UI can say something useful
/// instead of always blaming a stopped server.
class ApiErrorInfo {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool offline;
  const ApiErrorInfo(this.icon, this.color, this.title, this.detail, this.offline);
}

String _cleanError(String msg) => msg.replaceFirst('Exception: ', '').trim();

ApiErrorInfo describeApiError(Object error) {
  final msg = error.toString();
  final lower = msg.toLowerCase();
  if (msg.contains('401') || lower.contains('api key')) {
    return const ApiErrorInfo(
      Icons.lock_outline,
      AppColors.warning,
      'This server needs an API key',
      'Add your key with the key button in the sidebar, then retry.',
      false,
    );
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('clientexception') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('failed to fetch')) {
    return ApiErrorInfo(
      Icons.cloud_off,
      AppColors.breaking,
      "Can't reach the Wakegraph server",
      apiBase.isEmpty
          ? "The server isn't responding. Is it running?"
          : 'No response from $apiBase. Is the server running?',
      true,
    );
  }
  return ApiErrorInfo(
    Icons.error_outline,
    AppColors.breaking,
    'Something went wrong',
    _cleanError(msg),
    false,
  );
}

class ApiErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;
  const ApiErrorState({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final info = describeApiError(error);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, size: 40, color: info.color),
            const SizedBox(height: 12),
            Text(info.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(info.detail,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center),
            ),
            if (info.offline) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "./gradlew :server:bootRun --args='--spring.profiles.active=dev'",
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One consistent, calm placeholder for "there's nothing here yet" states across
/// the app: a muted icon, a title, an optional explanation and an optional CTA.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: muted.withOpacity(0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: muted),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(message!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
                    textAlign: TextAlign.center),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  const ScreenHeader(this.title, this.subtitle, {super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
