import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class TimeInfoCard extends StatelessWidget {
  const TimeInfoCard({
    super.key,
    required this.title,
    required this.value,
    this.highContrast = false,
  });

  final String title;
  final String value;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = highContrast ? AeternaTokens.countdownBackground : null;
    final fg = highContrast
        ? AeternaTokens.countdownForeground
        : scheme.onSurface;

    return SurfaceCard(
      style: highContrast ? SurfaceCardStyle.elevated : SurfaceCardStyle.filled,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: fg),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.displayLarge?.copyWith(color: fg, fontSize: 44),
            ),
          ],
        ),
      ),
    );
  }
}
