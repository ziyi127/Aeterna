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

class AeternaApp extends StatefulWidget {
  const AeternaApp({super.key});

  @override
  State<AeternaApp> createState() => _AeternaAppState();
}

class _AeternaAppState extends State<AeternaApp> {
  late final TimerController _controller;
  ThemeMode _themeMode = ThemeMode.system;
  ThemePalette _themePalette = ThemePalette.emerald;

  @override
  void initState() {
    super.initState();
    _controller = TimerController(exams: _mockExams(), ntpService: NtpService())
      ..start();

    // Load saved exams and add listener for auto-save
    _loadExamsAndSetupAutoSave();
    _loadDisplayPreferences();
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
      ConfigManager.saveExams(_controller.exams);
      final start = _controller.planStartDate ?? DateTime.now();
      final end = _controller.planEndDate ?? start;
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
