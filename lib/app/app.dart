import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/features/home/about_page.dart';
import 'package:aeterna/features/home/home_launcher_page.dart';
import 'package:aeterna/features/monitor/live_monitor_page.dart';
import 'package:aeterna/features/schedule/schedule_viewer_page.dart';
import 'package:aeterna/features/settings/ntp_config_page.dart';
import 'package:aeterna/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AeternaApp extends StatefulWidget {
  const AeternaApp({super.key});

  @override
  State<AeternaApp> createState() => _AeternaAppState();
}

class _AeternaAppState extends State<AeternaApp> {
  late final TimerController _controller;
  ThemeMode _themeMode = ThemeMode.system;
  ThemePalette _themePalette = ThemePalette.emerald;
  bool _showWelcome = false;
  String _appVersion = '--';
  String _lastSavedPlanKey = '';

  @override
  void initState() {
    super.initState();
    _controller = TimerController(exams: _mockExams(), ntpService: NtpService())
      ..start();

    // Load saved exams and add listener for auto-save
    _loadExamsAndSetupAutoSave();
    _loadDisplayPreferences();
    _loadSyncPreferences();
    _loadWelcomeState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) {
      return;
    }
    setState(() {
      _appVersion = info.version;
    });
  }

  Future<void> _loadDisplayPreferences() async {
    final settings = await ConfigManager.loadDisplaySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _themeMode = _themeModeFromKey(settings.themeMode);
      _themePalette = ThemePaletteLabel.fromKey(settings.themePalette);
    });
  }

  Future<void> _loadSyncPreferences() async {
    final sync = await ConfigManager.loadSyncSettings();
    _controller.setNtpAddress(sync.ntpAddress);
    _controller.setMode(sync.mode);
    _controller.setMaxDriftStepMs(sync.maxDriftStepMs);
  }

  Future<void> _loadWelcomeState() async {
    final shown = await ConfigManager.isWelcomeShown();
    if (!mounted) {
      return;
    }
    setState(() {
      _showWelcome = !shown;
    });
  }

  Future<void> _dismissWelcome() async {
    await ConfigManager.setWelcomeShown(true);
    if (!mounted) {
      return;
    }
    setState(() {
      _showWelcome = false;
    });
  }

  ThemeMode _themeModeFromKey(String key) {
    switch (key) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  String _themeModeKey(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> _updateTheme({
    required ThemeMode mode,
    required ThemePalette palette,
  }) async {
    if (_themeMode == mode && _themePalette == palette) {
      return;
    }
    setState(() {
      _themeMode = mode;
      _themePalette = palette;
    });

    final settings = await ConfigManager.loadDisplaySettings();
    await ConfigManager.saveDisplaySettings(
      settings.copyWith(
        themeMode: _themeModeKey(mode),
        themePalette: palette.key,
      ),
    );
  }

  Future<void> _loadExamsAndSetupAutoSave() async {
    final savedPlan = await ConfigManager.loadPlanConfig();
    if (savedPlan != null) {
      _controller.setExamMeta(
        examTitle: savedPlan.examTitle,
        startDate: savedPlan.startDate,
        endDate: savedPlan.endDate,
      );
      _controller.replaceAllExams(savedPlan.exams);
    }

    _controller.addListener(() {
      final start = _controller.planStartDate ?? DateTime.now();
      final end = _controller.planEndDate ?? start;
      final planJson = ConfigManager.exportToJson(
        _controller.exams,
        examTitle: _controller.examTitle,
        startDate: start,
        endDate: end,
      );
      if (_lastSavedPlanKey == planJson) {
        return;
      }
      _lastSavedPlanKey = planJson;
      ConfigManager.saveExams(_controller.exams);
      ConfigManager.savePlanConfig(
        ExamPlanConfig(
          examTitle: _controller.examTitle,
          startDate: start,
          endDate: end,
          exams: _controller.exams,
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TimerScope(
      controller: _controller,
      child: MaterialApp(
        title: '恒时 Aeterna',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(_themePalette),
        darkTheme: AppTheme.dark(_themePalette),
        themeMode: _themeMode,
        home: const HomeLauncherPage(),
        routes: {
          '/monitor': (_) => const LiveMonitorPage(),
          '/schedule': (_) => const ScheduleViewerPage(),
          '/settings': (_) => NtpConfigPage(
            currentThemeMode: _themeMode,
            currentThemePalette: _themePalette,
            onThemeChanged: _updateTheme,
          ),
          '/about': (_) => const AboutPage(),
        },
        builder: (context, child) {
          final page = child ?? const SizedBox.shrink();
          if (!_showWelcome) {
            return page;
          }
          return Stack(
            children: [
              page,
              Positioned.fill(
                child: _WelcomeOverlay(
                  version: _appVersion,
                  onStart: _dismissWelcome,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ExamSlot> _mockExams() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);

    return [
      ExamSlot(
        subject: '语文',
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 10, minutes: 20)),
      ),
      ExamSlot(
        subject: '数学',
        start: day.add(const Duration(hours: 10, minutes: 40)),
        end: day.add(const Duration(hours: 12)),
      ),
      ExamSlot(
        subject: '英语',
        start: day.add(const Duration(hours: 14)),
        end: day.add(const Duration(hours: 15, minutes: 20)),
      ),
      ExamSlot(
        subject: '物理',
        start: day.add(const Duration(hours: 15, minutes: 40)),
        end: day.add(const Duration(hours: 17)),
      ),
    ];
  }
}

class _WelcomeOverlay extends StatelessWidget {
  const _WelcomeOverlay({required this.version, required this.onStart});

  final String version;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '欢迎使用 恒时 Aeterna',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '恒时 Aeterna 是面向考场场景的考试看板与编排系统，提供考试计划管理、时间同步与放映展示。',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 14),
                  Text('版本号: v$version'),
                  const SizedBox(height: 6),
                  const Text('开源协议: Apache License 2.0'),
                  const SizedBox(height: 6),
                  const Text('维护者: ziyi127'),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('开始使用'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
