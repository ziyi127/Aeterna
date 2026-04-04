import 'dart:async';

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/core/resilience/circuit_breaker.dart';
import 'package:aeterna/core/update/update_service.dart';
import 'package:aeterna/features/home/about_page.dart';
import 'package:aeterna/features/home/home_launcher_page.dart';
import 'package:aeterna/features/monitor/live_monitor_page.dart';
import 'package:aeterna/features/schedule/schedule_page.dart';
import 'package:aeterna/features/settings/settings_page.dart';
import 'package:aeterna/shared/widgets/aeterna_logo.dart';
import 'package:aeterna/theme/app_theme.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AeternaApp extends StatefulWidget {
  // initialRoute is used when a restart must land directly on a specific page.
  const AeternaApp({super.key, this.initialRoute = '/'});

  final String initialRoute;

  @override
  State<AeternaApp> createState() => _AeternaAppState();
}

class _AeternaAppState extends State<AeternaApp> {
  late final TimerController _controller;
  ThemeMode _themeMode = ThemeMode.system;
  ThemePalette _themePalette = ThemePalette.emerald;
  bool _showWelcome = false;
  bool _welcomeClosing = false;
  String _appVersion = '--';
  String? _upgradeNotice;
  int _lastSavedPlanSignature = 0;
  final CircuitBreaker _planSaveBreaker = CircuitBreaker(
    failureThreshold: 3,
    recoveryTimeout: const Duration(seconds: 30),
    name: 'plan-save',
  );

  /// Compute a lightweight signature of the plan to detect actual changes
  /// without storing entire JSON strings (saves memory during timer ticks).
  int _computePlanSignature() {
    return Object.hash(
      _controller.planRevision,
      _controller.planStartDate?.millisecondsSinceEpoch,
      _controller.planEndDate?.millisecondsSinceEpoch,
    );
  }

  @override
  void initState() {
    super.initState();
    // Start with a small built-in plan so the interface has content before loading storage.
    _controller = TimerController(exams: _mockExams(), ntpService: NtpService())
      ..start();

    // Restore persisted state and wire the change listener after the controller exists.
    _loadExamsAndSetupAutoSave();
    _loadDisplayPreferences();
    _loadSyncPreferences();
    _loadWelcomeState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    // Version lookup is optional, so treat any failure as a soft error.
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _appVersion = info.version;
      });
    } catch (error) {
      debugPrint('load app version failed: $error');
    }
  }

  Future<void> _loadDisplayPreferences() async {
    // Theme and palette are loaded independently from the exam plan.
    try {
      final settings = await ConfigManager.loadDisplaySettings();
      if (!mounted) {
        return;
      }
      setState(() {
        _themeMode = _themeModeFromKey(settings.themeMode);
        _themePalette = ThemePaletteLabel.fromKey(settings.themePalette);
      });
    } catch (error) {
      debugPrint('load display preferences failed: $error');
    }
  }

  Future<void> _loadSyncPreferences() async {
    // Sync settings are pushed into the controller so the clock source matches storage.
    try {
      final sync = await ConfigManager.loadSyncSettings();
      _controller.setNtpServers(sync.ntpServers);
      _controller.setMode(sync.mode);
      _controller.setManualOffsetMs(sync.manualOffsetMs);
      _controller.setAutoSyncEnabled(sync.autoSyncEnabled);
      _controller.setAutoSyncIntervalMinutes(sync.autoSyncIntervalMinutes);
    } catch (error) {
      debugPrint('load sync preferences failed: $error');
    }
  }

  Future<void> _loadWelcomeState() async {
    // First launch and successful release upgrades both use the same welcome overlay.
    try {
      final shown = await ConfigManager.isWelcomeShown();
      final upgradeNotice = await UpdateService.consumeSuccessNotice();
      if (!mounted) {
        return;
      }
      setState(() {
        _upgradeNotice = upgradeNotice?.message;
        _showWelcome = !shown || upgradeNotice != null;
      });
    } catch (error) {
      debugPrint('load welcome state failed: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _showWelcome = true;
      });
    }
  }

  Future<void> _dismissWelcome() async {
    // Fade the overlay out before marking it as seen.
    if (_welcomeClosing || !_showWelcome) {
      return;
    }
    setState(() {
      _welcomeClosing = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 360));
    try {
      await ConfigManager.setWelcomeShown(true);
    } catch (error) {
      debugPrint('set welcome shown failed: $error');
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _showWelcome = false;
      _welcomeClosing = false;
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
    // Ignore no-op updates to avoid unnecessary writes.
    if (_themeMode == mode && _themePalette == palette) {
      return;
    }
    setState(() {
      _themeMode = mode;
      _themePalette = palette;
    });

    try {
      final settings = await ConfigManager.loadDisplaySettings();
      await ConfigManager.saveDisplaySettings(
        settings.copyWith(
          themeMode: _themeModeKey(mode),
          themePalette: palette.key,
        ),
      );
    } catch (error) {
      debugPrint('update theme persistence failed: $error');
    }
  }

  Future<void> _loadExamsAndSetupAutoSave() async {
    // Restore the last saved plan before listening for future edits.
    try {
      final savedPlan = await ConfigManager.loadPlanConfig();
      if (savedPlan != null) {
        _controller.setExamMeta(
          examTitle: savedPlan.examTitle,
          startDate: savedPlan.startDate,
          endDate: savedPlan.endDate,
        );
        _controller.replaceAllExams(savedPlan.exams);
      }
    } catch (error) {
      debugPrint('load exam plan failed: $error');
    }

    _controller.addListener(() {
      // The controller ticks every second, so the save trigger must stay cheap.
      final start = _controller.planStartDate ?? DateTime.now();
      final end = _controller.planEndDate ?? start;
      // Use lightweight signature to detect actual plan changes.
      // This avoids expensive JSON serialization on every second tick.
      final currentSignature = _computePlanSignature();
      if (_lastSavedPlanSignature == currentSignature) {
        return;
      }
      _lastSavedPlanSignature = currentSignature;
      unawaited(_savePlanState(start: start, end: end));
    });
  }

  Future<void> _savePlanState({
    required DateTime start,
    required DateTime end,
  }) async {
    // Save the plan list and metadata together so they remain consistent.
    await _planSaveBreaker.runOrNull(() async {
      await ConfigManager.saveExams(_controller.exams);
      await ConfigManager.savePlanConfig(
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
    // Build the root MaterialApp from the current theme, content, and resume route.
    return TimerScope(
      controller: _controller,
      child: MaterialApp(
        title: '恒时 Aeterna',
        debugShowCheckedModeBanner: false,
        themeAnimationDuration: AeternaTokens.motionDurationSlow,
        themeAnimationCurve: AeternaTokens.motionCurveStandard,
        theme: AppTheme.light(_themePalette),
        darkTheme: AppTheme.dark(_themePalette),
        themeMode: _themeMode,
        initialRoute: widget.initialRoute,
        home: const HomeLauncherPage(),
        routes: {
          '/monitor': (_) => const LiveMonitorPage(),
          '/schedule': (_) => const SchedulePage(),
          '/settings': (_) => SettingsPage(
            currentThemeMode: _themeMode,
            currentThemePalette: _themePalette,
            onThemeChanged: _updateTheme,
          ),
          '/about': (_) => const AboutPage(),
        },
        builder: (context, child) {
          // Keep the welcome overlay above every route until the user dismisses it.
          final page = child ?? const SizedBox.shrink();
          if (!_showWelcome) {
            return page;
          }
          return Stack(
            children: [
              page,
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _welcomeClosing ? 0 : 1,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: _welcomeClosing,
                    child: _WelcomeOverlay(
                      version: _appVersion,
                      upgradeNotice: _upgradeNotice,
                      onStart: _dismissWelcome,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ExamSlot> _mockExams() {
    // Seed the app with example exams so the UI is useful before any import.
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
  const _WelcomeOverlay({
    required this.version,
    required this.onStart,
    this.upgradeNotice,
  });

  final String version;
  final VoidCallback onStart;
  final String? upgradeNotice;

  @override
  Widget build(BuildContext context) {
    // The overlay intentionally occupies the entire screen and blocks interaction.
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.92, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.25, -0.45),
                radius: 1.2,
                colors: [
                  scheme.primary.withValues(alpha: 0.32),
                  Colors.black.withValues(alpha: 0.9),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AeternaLogo(size: 96, strokeWidth: 7),
                  const SizedBox(height: 20),
                  Text(
                    '欢迎使用 恒时 Aeterna',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(
                      '面向考场场景的考试看板与编排系统，提供考试计划管理、时间同步和高可读放映展示。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (upgradeNotice != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.16),
                        borderRadius: AeternaTokens.radiusControl,
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        upgradeNotice!,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: AeternaTokens.radiusControl,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircleAvatar(
                          radius: 22,
                          backgroundImage: NetworkImage(
                            'https://avatars.githubusercontent.com/ziyi127',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '维护者 ziyi127',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            Text(
                              'v$version  ·  Apache License 2.0',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('开始使用'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 14,
                      ),
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
