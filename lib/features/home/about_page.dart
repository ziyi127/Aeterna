import 'package:aeterna/shared/widgets/aeterna_logo.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const String _githubProfileUrl = 'https://github.com/ziyi127';
const String _githubRepoUrl = 'https://github.com/ziyi127/Aeterna';
const String _githubAvatarUrl = 'https://github.com/ziyi127.png';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      appBar: AppBar(title: const Text('关于 Aeterna')),
      body: ListView(
        padding: AeternaTokens.pagePaddingFor(width),
        children: const [
          _HeroCard(),
          SizedBox(height: 14),
          _FeatureCard(),
          SizedBox(height: 14),
          _OpenSourceCard(),
          SizedBox(height: 14),
          _MaintainerCard(),
          SizedBox(height: 14),
          _ReleaseCard(),
          SizedBox(height: 14),
          _TipsCard(),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AeternaLogo(size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '恒时 Aeterna',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    const _VersionCaption(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Aeterna 是面向考场一体机的考试看板与编排系统，聚焦“稳定时钟、清晰信息、低误操作”。',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.filled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('核心能力', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const _FeatureRow(
            icon: Icons.schedule_outlined,
            text: '多天考试计划编排与导入导出',
          ),
          const SizedBox(height: 8),
          const _FeatureRow(
            icon: Icons.timer_outlined,
            text: '离线/内网/云端时间同步与漂移校正',
          ),
          const SizedBox(height: 8),
          const _FeatureRow(
            icon: Icons.cast_for_education,
            text: '全屏放映模式与关键节点提醒',
          ),
          const SizedBox(height: 8),
          const _FeatureRow(
            icon: Icons.palette_outlined,
            text: '主题配色动态切换与显示参数配置',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard();

  Future<void> _openRepo() async {
    final uri = Uri.parse(_githubRepoUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('版本信息', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          const _VersionLine(),
          const SizedBox(height: 6),
          Text(
            '发布日期: 2026-03-28',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '运行环境: Flutter Desktop / Linux',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          SelectableText(
            '仓库地址: $_githubRepoUrl',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _openRepo,
            icon: const Icon(Icons.open_in_new),
            label: const Text('打开仓库地址'),
          ),
        ],
      ),
    );
  }
}

class _VersionCaption extends StatelessWidget {
  const _VersionCaption();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData ? snapshot.data!.version : '--';
        return Text(
          'Exam Dashboard v$version',
          style: Theme.of(context).textTheme.bodyMedium,
        );
      },
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData ? snapshot.data!.version : '--';
        return Text(
          '当前版本: v$version',
          style: Theme.of(context).textTheme.bodyMedium,
        );
      },
    );
  }
}

class _OpenSourceCard extends StatelessWidget {
  const _OpenSourceCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.filled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('开源协议', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            '本项目基于 Apache License 2.0 开源，允许商业使用、修改与再发布。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '使用与分发时请保留版权与许可证声明。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _MaintainerCard extends StatelessWidget {
  const _MaintainerCard();

  Future<void> _openProfile() async {
    final uri = Uri.parse(_githubProfileUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.elevated,
      child: InkWell(
        borderRadius: BorderRadius.circular(AeternaTokens.superRadius),
        onTap: _openProfile,
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              child: ClipOval(
                child: Image.network(
                  _githubAvatarUrl,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFFCFD4DA),
                      alignment: Alignment.center,
                      child: const Text(
                        'Z',
                        style: TextStyle(
                          color: Color(0xFF374151),
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('维护者', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    'ziyi127',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _githubProfileUrl,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new),
          ],
        ),
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.filled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('建议流程', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(
            '1. 在“计划”中维护考试安排',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '2. 在“设置”中保存时间源与显示参数',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          Text(
            '3. 同步时间后进入“放映”模式',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
