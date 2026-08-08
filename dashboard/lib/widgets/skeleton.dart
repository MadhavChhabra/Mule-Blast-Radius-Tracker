import 'package:flutter/material.dart';

import '../theme.dart';

/// Loading (2g): a highlight band sweeping across opaque plates, 400px wide, -400 → 400 over 1.4s.
/// Elements stagger 150ms apart so the surface reads as filling in rather than pulsing as one.
class Shimmer extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const Shimmer({super.key, required this.child, this.delay = Duration.zero});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  /// The stagger is a phase offset on a shared 1.4s cycle rather than a delayed start — a pending
  /// timer would outlive the widget tree and trip the test binding.
  double get _phase => (widget.delay.inMilliseconds % 1400) / 1400.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _base = Color(0xFF15171E);
  static const _highlight = Color(0xFF1E2129);

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = (_c.value + _phase) % 1.0;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [_base, _highlight, _base],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t.clamp(0.0, 1.0),
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 5});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF15171E),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// The default loading state: a title line, a row of plates, then tapering text lines.
class SkeletonList extends StatelessWidget {
  final int rows;
  const SkeletonList({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
        const Shimmer(child: SkeletonBox(width: 180, height: 16)),
        const SizedBox(height: 16),
        Row(children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Shimmer(
                delay: Duration(milliseconds: 150 * i),
                child: const SkeletonBox(height: 66, radius: AppRadius.tile),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 12),
        for (int i = 0; i < rows; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Shimmer(
            delay: Duration(milliseconds: 200 + 100 * i),
            child: SkeletonBox(
                width: [double.infinity, 300.0, 220.0, 160.0][i % 4] == double.infinity
                    ? null
                    : [double.infinity, 300.0, 220.0, 160.0][i % 4],
                height: 12),
          ),
        ],
      ]),
    );
  }
}
