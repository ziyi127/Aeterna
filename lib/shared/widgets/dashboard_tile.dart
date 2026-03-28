import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class DashboardTile extends StatelessWidget {
  const DashboardTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.highlight = false,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool highlight;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = highlight ? scheme.onPrimary : scheme.onSurface;
    final color = highlight ? scheme.primary : null;
    final trailingWidgets = trailing == null ? null : <Widget>[trailing!];

    return SurfaceCard(
      style: highlight ? SurfaceCardStyle.elevated : SurfaceCardStyle.filled,
      padding: const EdgeInsets.all(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Icon(icon, size: 34, color: foreground),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              ...?trailingWidgets,
            ],
          ),
        ),
      ),
    );
  }
}
