import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/dashboard_tile.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class HomeLauncherPage extends StatelessWidget {
  const HomeLauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = TimerScope.of(context);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final compact = width < 940;
          final crossAxisCount = width < 760 ? 1 : 2;
          final tileAspect = width > 1800 ? 1.9 : (compact ? 2.1 : 1.55);

          return Padding(
            padding: AeternaTokens.pagePaddingFor(width),
            child: Column(
              children: [
                _LauncherHeader(compact: compact),
                const SizedBox(height: 24),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: tileAspect,
                    children: [
                      DashboardTile(
                        title: '放映 Projector',
                        subtitle: '进入考场看板，展示实时考试进度',
                        icon: Icons.cast_for_education,
                        highlight: true,
                        onTap: () =>
                            Navigator.of(context).pushNamed('/monitor'),
                      ),
                      DashboardTile(
                        title: '计划 Schedule',
                        subtitle: '今日 ${controller.exams.length} 场考试，支持直接编辑计划',
                        icon: Icons.view_timeline_outlined,
                        onTap: () =>
                            Navigator.of(context).pushNamed('/schedule'),
                      ),
                      DashboardTile(
                        title: '设置 Settings',
                        subtitle: '时间同步与系统参数',
                        icon: Icons.settings_outlined,
                        trailing: Chip(label: Text(controller.modeLabel)),
                        onTap: () =>
                            Navigator.of(context).pushNamed('/settings'),
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
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '恒时 Aeterna',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Align(alignment: Alignment.centerLeft, child: _actions()),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            '恒时 Aeterna',
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        _actions(),
      ],
    );
  }

  Widget _actions() {
    return SurfaceCard(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CapsuleAction(icon: Icons.minimize, label: '最小化'),
          const SizedBox(width: 8),
          _CapsuleAction(icon: Icons.close, label: '退出'),
          const SizedBox(width: 8),
          _CapsuleAction(icon: Icons.fullscreen, label: '全屏'),
        ],
      ),
    );
  }
}

class _CapsuleAction extends StatelessWidget {
  const _CapsuleAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  Future<void> _onPressed() async {
    switch (label) {
      case '最小化':
        await windowManager.minimize();
        break;
      case '全屏':
        final isFullScreen = await windowManager.isFullScreen();
        await windowManager.setFullScreen(!isFullScreen);
        break;
      case '退出':
        await windowManager.close();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(120, AeternaTokens.touchMinHeight),
      ),
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
      trailing: const CircleAvatar(
        radius: 18,
        child: Icon(Icons.dashboard_customize_outlined),
      ),
      onTap: onTap,
    );
  }
}
