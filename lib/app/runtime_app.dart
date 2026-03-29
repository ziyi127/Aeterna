import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/features/monitor/live_monitor_page.dart';
import 'package:aeterna/theme/app_theme.dart';
import 'package:flutter/material.dart';

class AeternaRuntimeApp extends StatefulWidget {
  const AeternaRuntimeApp({super.key});

  @override
  State<AeternaRuntimeApp> createState() => _AeternaRuntimeAppState();
}

class _AeternaRuntimeAppState extends State<AeternaRuntimeApp> {
  late final TimerController _controller;
  ThemeMode _themeMode = ThemeMode.system;
  ThemePalette _themePalette = ThemePalette.emerald;

  @override
  void initState() {
    super.initState();
    _controller = TimerController(exams: _runtimeFallbackExams(), ntpService: NtpService())
      ..start();
    _loadRuntimeConfig();
  }

  Future<void> _loadRuntimeConfig() async {
    final display = await ConfigManager.loadDisplaySettings();
    final sync = await ConfigManager.loadSyncSettings();
    final plan = await ConfigManager.loadPlanConfig();

    _controller.setNtpAddress(sync.ntpAddress);
    _controller.setMode(sync.mode);
    _controller.setMaxDriftStepMs(sync.maxDriftStepMs);

    if (plan != null) {
      _controller.setExamMeta(
        examTitle: plan.examTitle,
        startDate: plan.startDate,
        endDate: plan.endDate,
      );
      _controller.replaceAllExams(plan.exams);
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _themeMode = _themeModeFromKey(display.themeMode);
      _themePalette = ThemePaletteLabel.fromKey(display.themePalette);
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
        title: '恒时 Aeterna Runtime',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(_themePalette),
        darkTheme: AppTheme.dark(_themePalette),
        themeMode: _themeMode,
        home: const LiveMonitorPage(),
      ),
    );
  }

  List<ExamSlot> _runtimeFallbackExams() {
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
    ];
  }
}
