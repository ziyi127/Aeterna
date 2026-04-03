import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/aeterna_logo.dart';
import 'package:aeterna/shared/widgets/aeterna_reveal.dart';
import 'package:aeterna/shared/widgets/dashboard_tile.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class HomeLauncherPage extends StatelessWidget {
  const HomeLauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TimerScope.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final compact = width < 940 || height < 760;
          final crossAxisCount = width < 760 ? 1 : 2;
          const spacing = 18.0;
          final rows = (4 / crossAxisCount).ceil();
          final tileWidth =
            (width - (crossAxisCount - 1) * spacing) / crossAxisCount;
          final tileHeight = (height - 120 - (rows - 1) * spacing) / rows;
          final tileAspect =
            (tileWidth / tileHeight).clamp(1.0, width > 1800 ? 2.0 : 2.35);

          return Padding(
            padding: AeternaTokens.pagePaddingFor(width),
            child: Column(
              children: [
                AeternaReveal(
                  delay: const Duration(milliseconds: 40),
                  child: _LauncherHeader(compact: compact),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: tileAspect,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      DashboardTile(
                        title: '放映 Projector',
                        subtitle: '进入考场看板，展示实时考试进度',
                        icon: Icons.cast_for_education,
                        highlight: true,
                        onTap: () => Navigator.of(context).pushNamed('/monitor'),
                      ),
                      DashboardTile(
                        title: '计划 Schedule',
                        subtitle: '今日 ${controller.exams.length} 场考试，支持直接编辑计划',
                        icon: Icons.view_timeline_outlined,
                        onTap: () => Navigator.of(context).pushNamed('/schedule'),
                      ),
                      DashboardTile(
                        title: '设置 Settings',
                        subtitle: '时间同步与系统参数',
                        icon: Icons.settings_outlined,
                        onTap: () => Navigator.of(context).pushNamed('/settings'),
                      ),
                      _AboutTile(
                        onTap: () => Navigator.of(context).pushNamed('/about'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LauncherHeader extends StatelessWidget {
  const _LauncherHeader({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AeternaLogo(size: 38, strokeWidth: 5),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '恒时 Aeterna',
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardTile(
      title: '关于 About',
      subtitle: '查看版本、特性与使用说明',
      icon: Icons.info_outline,
      trailing: const AeternaLogo(size: 34, strokeWidth: 4),
      onTap: onTap,
    );
  }
}
