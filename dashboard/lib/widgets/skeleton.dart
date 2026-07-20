import 'package:flutter/material.dart';

/// A shimmering placeholder used while data loads, instead of a bare spinner.
/// Wrap opaque grey [SkeletonBox]es in a [Shimmer] and a highlight band sweeps
/// across them.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1250))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2A2D3A) : const Color(0xFFE9EBEF);
    final highlight = dark ? const Color(0xFF373B4C) : const Color(0xFFF6F7F9);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [base, highlight, base],
          stops: [
            (_c.value - 0.3).clamp(0.0, 1.0),
            _c.value.clamp(0.0, 1.0),
            (_c.value + 0.3).clamp(0.0, 1.0),
          ],
        ).createShader(rect),
        child: child,
      ),
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EBEF),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A neutral card-shaped placeholder: a title line and a few text lines.
/// Used as the default loading state for [AsyncView].
class SkeletonList extends StatelessWidget {
  final int rows;
  const SkeletonList({super.key, this.rows = 4});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: const EdgeInsets.all(24),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, i) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 180, height: 16),
              SizedBox(height: 12),
              SkeletonBox(height: 10),
              SizedBox(height: 8),
              SkeletonBox(width: 260, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
