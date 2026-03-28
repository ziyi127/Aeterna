import 'package:flutter/material.dart';

class AeternaLogo extends StatelessWidget {
  const AeternaLogo({
    super.key,
    this.size = 56,
    this.color,
    this.useSuperellipse = true,
    this.strokeWidth = 8,
    this.dotRatio = 0.14,
    this.dotOffsetRatio = 0.2,
  });

  final double size;
  final Color? color;
  final bool useSuperellipse;
  final double strokeWidth;
  final double dotRatio;
  final double dotOffsetRatio;

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? Theme.of(context).colorScheme.primary;
    final dotSize = (size * dotRatio).clamp(6.0, size).toDouble();
    final dotOffset = (size * dotOffsetRatio).clamp(0.0, size).toDouble();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: useSuperellipse ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: useSuperellipse
                    ? BorderRadius.circular(size * 0.34)
                    : null,
                border: Border.all(color: logoColor, width: strokeWidth),
              ),
            ),
          ),
          Positioned(
            top: dotOffset,
            right: dotOffset,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: logoColor,
                shape: BoxShape.circle,
              ),
              child: SizedBox(width: dotSize, height: dotSize),
            ),
          ),
        ],
      ),
    );
  }
}
