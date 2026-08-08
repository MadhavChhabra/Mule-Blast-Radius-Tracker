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

/// What kind of failure an API call hit, so the UI can say something useful instead of always
/// blaming a stopped server.
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
      'Add your key with the key button in the top bar, then retry.',
      false,
    );
  }
  if (lower.contains('did not respond within')) {
    return const ApiErrorInfo(
      Icons.hourglass_disabled_outlined,
      AppColors.warning,
      'The server took too long to answer',
      'It may be busy running a sync. Wait a moment and retry — nothing was lost.',
      false,
    );
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('clientexception') ||
      lower.contains('could not reach') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('failed to fetch')) {
    return ApiErrorInfo(
      Icons.cloud_off,
      AppColors.breaking,
      "Can't reach the BlipRadius server",
      apiBase.isEmpty
          ? 'No response from this address. Nothing was lost — your last synced estate is '
              'still on the server.'
          : 'No response from $apiBase. Nothing was lost — your last synced estate is '
              'still on the server.',
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
    return _StateShell(
      kicker: info.offline ? 'SERVER UNREACHABLE' : 'SOMETHING WENT WRONG',
      children: [
        Icon(info.icon, size: 30, color: info.color),
        const SizedBox(height: 14),
        Text(info.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Text(info.detail,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.55, color: AppColors.textMuted)),
        ),
        if (info.offline && apiBase.contains('localhost')) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.fillSubtle,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text('./gradlew :server:bootRun', style: monoData(size: 11)),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}

/// One calm placeholder for "there's nothing here yet". Every empty state names *why* it is empty
/// and offers the one action that fixes it.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final String kicker;

  /// Draws three dashed node outlines instead of an icon — used where the missing thing is
  /// structure (endpoints, a map) rather than a record.
  final bool ghostNodes;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.kicker = 'NOTHING TO SHOW YET',
    this.ghostNodes = false,
  });

  @override
  Widget build(BuildContext context) {
    return _StateShell(
      kicker: kicker,
      children: [
        if (ghostNodes)
          Opacity(
            opacity: 0.5,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                CustomPaint(
                  size: const Size(44, 22),
                  painter: _DashedSlotPainter(),
                ),
              ],
            ]),
          )
        else
          Icon(icon, size: 30, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (message != null) ...[
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(message!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, height: 1.55, color: AppColors.textMuted)),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 16),
          action!,
        ],
      ],
    );
  }
}

/// "All clear" is a real answer, not an absence of data — so it gets its own affirmative state.
class AllClearState extends StatelessWidget {
  final String title;
  final String message;
  final int? depthPercent;
  const AllClearState({
    super.key,
    required this.title,
    required this.message,
    this.depthPercent,
  });

  @override
  Widget build(BuildContext context) {
    return _StateShell(
      kicker: 'ALL CLEAR',
      children: [
        const Icon(Icons.verified, size: 30, color: AppColors.additive),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.55, color: AppColors.textMuted)),
        ),
        if (depthPercent != null) ...[
          const SizedBox(height: 14),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: AppColors.additive, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 7),
            Text('ANSWER DEPTH $depthPercent%',
                style: monoData(size: 10.5, color: AppColors.additive)),
          ]),
        ],
      ],
    );
  }
}

/// Shared frame: a mono kicker pinned top-left, content centred beneath it.
///
/// Sized with a Stack rather than an Expanded so it is safe both on a bounded surface and inside a
/// scrolling parent — these states get embedded in both.
class _StateShell extends StatelessWidget {
  final String kicker;
  final List<Widget> children;
  const _StateShell({required this.kicker, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 240),
          child: Stack(children: [
            Positioned(top: 0, left: 0, child: Text(kicker, style: monoLabel())),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ]),
        ),
      );
}

class _DashedSlotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withOpacity(0.2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(7)));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, (d + 4).clamp(0, metric.length)), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedSlotPainter oldDelegate) => false;
}

class ScreenHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  const ScreenHeader(this.title, this.subtitle, {super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.5)),
          ]),
        ),
        ...actions,
      ]),
    );
  }
}
