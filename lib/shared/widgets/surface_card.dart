import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

enum SurfaceCardStyle { filled, elevated }

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.style = SurfaceCardStyle.filled,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final SurfaceCardStyle style;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
    );

    final content = Padding(padding: padding, child: child);

    if (style == SurfaceCardStyle.elevated) {
      return Card(shape: shape, elevation: 4, child: content);
    }
    return Card(shape: shape, elevation: 0, child: content);
  }
}
