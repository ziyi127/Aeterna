import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/exit_password_dialog.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({super.key});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  static const String _defaultExamInfo = '认真考试，仔细检查';
  static const MethodChannel _windowSecurityChannel = MethodChannel(
    'aeterna/window_security',
  );
  static const Duration _overlayVisibleDuration = Duration(seconds: 3);
  static const Duration _exitHoldTarget = Duration(seconds: 5);
  static const Duration _reminderShowDuration = Duration(seconds: 4);

  DisplaySettings _settings = const DisplaySettings(
    fontScale: 1.0,
    roomLabel: '试室 A01',
  );
  bool _overlayVisible = true;
  bool _isHoldingExit = false;
  bool _isHoldingSettings = false;
  Duration _holdElapsed = Duration.zero;
  Duration _settingsHoldElapsed = Duration.zero;

  Timer? _overlayTimer;
  Timer? _exitHoldTimer;
  Timer? _settingsHoldTimer;
  Timer? _reminderTimer;

  bool _enteredFullscreen = false;
  bool _wasFullscreen = false;
  bool _wasAlwaysOnTop = false;
  bool _enteredAlwaysOnTop = false;
  bool _windowsUiAccessEnabled = false;
  Timer? _desktopLockKeepAliveTimer;

  TimerController? _boundController;
  final Set<String> _firedReminderKeys = <String>{};
  final Queue<_ReminderPayload> _reminderQueue = Queue<_ReminderPayload>();
  _ReminderPayload? _activeReminder;

  DateTime? _lastReminderCleanupDate;

  @override
  void initState() {
    super.initState();
    _loadDisplaySettings();
    _showControlsTemporarily();
    // Delay presentation mode entry until window is fully initialized (post-frame).
    // This prevents null-pointer crashes on macOS when querying window state before
    // the platform window is fully created.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterPresentationMode();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = TimerScope.of(context);
    if (_boundController == controller) {
      return;
    }
    _boundController?.removeListener(_onControllerTick);
    _boundController = controller;
    _boundController?.addListener(_onControllerTick);
  }

  @override
  void dispose() {
    _boundController?.removeListener(_onControllerTick);
    _overlayTimer?.cancel();
    _exitHoldTimer?.cancel();
    _settingsHoldTimer?.cancel();
    _reminderTimer?.cancel();
    _desktopLockKeepAliveTimer?.cancel();
    _leavePresentationMode();
    super.dispose();
  }

  Future<bool> _isWindowsUiAccessEnabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return false;
    }
    try {
      final result = await _windowSecurityChannel.invokeMethod<bool>(
        'isUiAccessEnabled',
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  void _startDesktopLockKeepAlive() {
    if (kIsWeb) {
      return;
    }

    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (!isDesktop) {
      return;
    }

    // Windows without UIAccess uses degraded strategy:
    // keep forcing fullscreen + top-most + focus to reduce overlay loss.
    final isWindowsWithoutUiAccess =
        defaultTargetPlatform == TargetPlatform.windows &&
        !_windowsUiAccessEnabled;
    final keepAliveInterval = isWindowsWithoutUiAccess
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 900);

    _desktopLockKeepAliveTimer?.cancel();
    _desktopLockKeepAliveTimer = Timer.periodic(
      keepAliveInterval,
      (_) async {
        try {
          await windowManager.setFullScreen(true);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.focus();
        } catch (_) {
          // Ignore unsupported behavior.
        }
      },
    );
  }

  void _onControllerTick() {
    _checkReminderMoments();
  }

  Future<void> _ensurePresentationWindowState() async {
    // Windows fullscreen may fail intermittently when transition races with
    // native window events, so retry a few times with fallback maximize.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    for (var i = 0; i < 3; i++) {
      try {
        final fullscreen = await windowManager.isFullScreen().timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => false,
        );
        if (fullscreen) {
          return;
        }
        await windowManager.maximize();
        await windowManager.setFullScreen(true);
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } catch (_) {
        // Ignore transient platform failures and continue retrying.
      }
    }
  }

  Future<void> _enterPresentationMode() async {
    if (kIsWeb) {
      return;
    }

    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;

    _windowsUiAccessEnabled = await _isWindowsUiAccessEnabled();

    // Step 1: Try fullscreen first for immersive presentation.
    try {
      // Safely query fullscreen state, defaulting to false if window is unavailable.
      _wasFullscreen = await windowManager.isFullScreen().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => false,
      );
      if (!_wasFullscreen) {
        await windowManager.setFullScreen(true);
        _enteredFullscreen = true;
      }
    } catch (_) {
      // Ignore unsupported fullscreen behavior and continue with top-most mode.
      // Window may not be fully initialized yet on some platforms.
      _wasFullscreen = false;
    }

    // Step 2: Cross-platform top-most fallback (uiAccess-like behavior).
    if (isDesktop) {
      try {
        // Safely query always-on-top state, defaulting to false if window is unavailable.
        _wasAlwaysOnTop = await windowManager.isAlwaysOnTop().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => false,
        );
        if (!_wasAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(true);
          _enteredAlwaysOnTop = true;
        }
      } catch (_) {
        // Ignore unsupported always-on-top behavior.
        // Window may not be fully initialized yet on some platforms.
        _wasAlwaysOnTop = false;
      }

      try {
        await windowManager.focus();
      } catch (_) {
        // Ignore unsupported focus behavior.
      }

      await _ensurePresentationWindowState();

      _startDesktopLockKeepAlive();
    }
  }

  Future<void> _leavePresentationMode() async {
    if (kIsWeb) {
      return;
    }

    _desktopLockKeepAliveTimer?.cancel();
    _desktopLockKeepAliveTimer = null;

    // Restore always-on-top state first.
    if (_enteredAlwaysOnTop) {
      try {
        await windowManager.setAlwaysOnTop(false);
        _enteredAlwaysOnTop = false;
      } catch (_) {
        // Ignore unsupported always-on-top behavior.
      }
    }

    // Restore fullscreen state.
    if (_enteredFullscreen) {
      try {
        await windowManager.setFullScreen(false);
        _enteredFullscreen = false;
      } catch (_) {
        // Ignore unsupported fullscreen behavior.
      }
    }
  }

  Future<void> _loadDisplaySettings() async {
    final loaded = await ConfigManager.loadDisplaySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = loaded;
    });
  }

  void _showControlsTemporarily() {
    if (!mounted) {
      return;
    }
    if (!_overlayVisible) {
      setState(() => _overlayVisible = true);
    }
    _overlayTimer?.cancel();
    _overlayTimer = Timer(_overlayVisibleDuration, () {
      if (!mounted || _isHoldingExit || _isHoldingSettings) {
        return;
      }
      if (_overlayVisible) {
        setState(() => _overlayVisible = false);
      }
    });
  }

  void _startExitHold() {
    if (_isHoldingExit) {
      return;
    }
    _showControlsTemporarily();
    setState(() {
      _isHoldingExit = true;
      _holdElapsed = Duration.zero;
    });

    _exitHoldTimer?.cancel();
    _exitHoldTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final next = _holdElapsed + const Duration(milliseconds: 50);
      if (next >= _exitHoldTarget) {
        timer.cancel();
        _exitHoldTimer = null;
        _confirmExitPresentation();
        return;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _holdElapsed = next;
      });
    });
  }

  void _cancelExitHold() {
    if (!_isHoldingExit) {
      return;
    }
    _exitHoldTimer?.cancel();
    _exitHoldTimer = null;
    setState(() {
      _isHoldingExit = false;
      _holdElapsed = Duration.zero;
    });
    _showControlsTemporarily();
  }

  void _startSettingsHold() {
    if (_isHoldingSettings) {
      return;
    }
    _showControlsTemporarily();
    setState(() {
      _isHoldingSettings = true;
      _settingsHoldElapsed = Duration.zero;
    });

    _settingsHoldTimer?.cancel();
    _settingsHoldTimer = Timer.periodic(const Duration(milliseconds: 50), (
      timer,
    ) {
      final next = _settingsHoldElapsed + const Duration(milliseconds: 50);
      if (next >= _exitHoldTarget) {
        timer.cancel();
        _settingsHoldTimer = null;
        _confirmOpenSettings();
        return;
      }
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _settingsHoldElapsed = next;
      });
    });
  }

  void _cancelSettingsHold() {
    if (!_isHoldingSettings) {
      return;
    }
    _settingsHoldTimer?.cancel();
    _settingsHoldTimer = null;
    setState(() {
      _isHoldingSettings = false;
      _settingsHoldElapsed = Duration.zero;
    });
    _showControlsTemporarily();
  }

  Future<void> _confirmOpenSettings() async {
    if (!mounted) {
      return;
    }
    _settingsHoldTimer?.cancel();
    _settingsHoldTimer = null;
    setState(() {
      _isHoldingSettings = false;
      _settingsHoldElapsed = Duration.zero;
    });

    final needsPassword =
        _settings.exitPasswordEnabled && _settings.exitPassword.isNotEmpty;
    if (needsPassword) {
      final result = await ExitPasswordDialog.show(context);
      if (!mounted) {
        return;
      }
      if (result != _settings.exitPassword) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码错误，无法打开设置')));
        return;
      }
    }

    await _openDisplaySettingsDialog();
  }

  Future<void> _confirmExitPresentation() async {
    if (!mounted) {
      return;
    }
    _exitHoldTimer?.cancel();
    _exitHoldTimer = null;
    setState(() {
      _isHoldingExit = false;
      _holdElapsed = Duration.zero;
    });

    final controller = _boundController ?? TimerScope.of(context);
    final planStart = controller.planStartDate;
    final planEnd = controller.planEndDate;
    final isInExamPeriod =
      planStart != null &&
      planEnd != null &&
      !controller.now.isBefore(planStart) &&
      controller.now.isBefore(planEnd.add(const Duration(days: 1)));
    final bypassBySafeMode = _settings.safeMode && isInExamPeriod;
    final needsPassword =
        _settings.exitPasswordEnabled &&
        _settings.exitPassword.isNotEmpty &&
        !bypassBySafeMode;

    if (needsPassword) {
      final result = await ExitPasswordDialog.show(context);
      if (!mounted) {
        return;
      }
      if (result != _settings.exitPassword) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码错误，无法退出')));
        return;
      }
    }

    await _leavePresentationMode();
    if (!mounted) {
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openDisplaySettingsDialog() async {
    _showControlsTemporarily();
    double localScale = _settings.fontScale;

    final result = await showDialog<DisplaySettings>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('放映设置'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('字体大小倍率: ${localScale.toStringAsFixed(2)}x'),
                    Slider(
                      min: 0.7,
                      max: 1.8,
                      divisions: 11,
                      value: localScale,
                      onChanged: (v) => setLocalState(() => localScale = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '试室号请到“设置 Settings”页面修改。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(
                      _settings.copyWith(fontScale: localScale),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _settings = result;
    });
    await ConfigManager.saveDisplaySettings(result);
  }

  void _checkReminderMoments() {
    final controller = _boundController;
    if (controller == null) {
      return;
    }

    final now = controller.now;
    for (final exam in controller.exams) {
      _enqueueReminderIfDue(
        key: '${exam.start.toIso8601String()}|pre_start_15',
        triggerAt: exam.start.subtract(const Duration(minutes: 15)),
        now: now,
        payload: _ReminderPayload(
          title: '距离开始还有 15 分钟',
          subtitle: '${exam.subject} 即将开考',
          color: Colors.orange,
        ),
      );

      _enqueueReminderIfDue(
        key: '${exam.start.toIso8601String()}|start',
        triggerAt: exam.start,
        now: now,
        payload: _ReminderPayload(
          title: '考试开始',
          subtitle: '${exam.subject} 已开始',
          color: Colors.red,
        ),
      );

      final beforeEnd = exam.end.subtract(const Duration(minutes: 15));
      if (beforeEnd.isAfter(exam.start)) {
        _enqueueReminderIfDue(
          key: '${exam.start.toIso8601String()}|pre_end_15',
          triggerAt: beforeEnd,
          now: now,
          payload: _ReminderPayload(
            title: '距离结束还有 15 分钟',
            subtitle: '${exam.subject} 即将结束',
            color: Colors.deepOrange,
          ),
        );
      }

      _enqueueReminderIfDue(
        key: '${exam.start.toIso8601String()}|end',
        triggerAt: exam.end,
        now: now,
        payload: _ReminderPayload(
          title: '考试结束',
          subtitle: '${exam.subject} 已结束',
          color: Colors.green,
        ),
      );
    }

    _cleanupExpiredReminders();

    _showNextReminderIfIdle();
  }

  void _cleanupExpiredReminders() {
    final now = DateTime.now();
    final last = _lastReminderCleanupDate;
    if (last == null ||
        last.year != now.year ||
        last.month != now.month ||
        last.day != now.day) {
      _firedReminderKeys.clear();
      _lastReminderCleanupDate = now;
    }
  }

  void _enqueueReminderIfDue({
    required String key,
    required DateTime triggerAt,
    required DateTime now,
    required _ReminderPayload payload,
  }) {
    if (_firedReminderKeys.contains(key)) {
      return;
    }

    final diffSeconds = now.difference(triggerAt).inSeconds;
    if (diffSeconds.abs() > 2) {
      return;
    }

    _firedReminderKeys.add(key);
    _reminderQueue.add(payload);
  }

  void _showNextReminderIfIdle() {
    if (!mounted || _activeReminder != null || _reminderQueue.isEmpty) {
      return;
    }

    setState(() {
      _activeReminder = _reminderQueue.removeFirst();
      _overlayVisible = false;
    });

    _reminderTimer?.cancel();
    _reminderTimer = Timer(_reminderShowDuration, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _activeReminder = null;
      });
      _showNextReminderIfIdle();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = TimerScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final shortestSide = math.min(viewport.width, viewport.height);
    final panelScale = _settings.fontScale.clamp(0.7, 1.8);
    final panelGap = (shortestSide * 0.012).clamp(8.0, 18.0).toDouble();
    final planExamInfo = controller.exams
      .map((e) => e.message.trim())
      .firstWhere((m) => m.isNotEmpty, orElse: () => _defaultExamInfo);
    final currentExamInfo =
      controller.activeExam?.message.trim().isNotEmpty == true
      ? controller.activeExam!.message.trim()
      : planExamInfo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Prevent Android back button from exiting presentation mode.
        // Users must use the long-press exit button instead.
      },
      child: Listener(
        onPointerDown: (_) => _showControlsTemporarily(),
        onPointerMove: (_) => _showControlsTemporarily(),
        onPointerSignal: (_) => _showControlsTemporarily(),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _showControlsTemporarily,
          child: Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: Stack(
              children: [
                Padding(
                  padding: AeternaTokens.pagePaddingFor(
                    MediaQuery.sizeOf(context).width,
                  ),
                  child: Column(
                    children: [
                      _TopInfoBar(
                        examTitle: controller.examTitle,
                        examInfo: currentExamInfo,
                        roomLabel: _settings.roomLabel,
                        fontScale: _settings.fontScale,
                        compact: viewport.width < 980 || viewport.height < 640,
                      ),
                      SizedBox(height: panelGap),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide =
                                constraints.maxWidth >= 1200 &&
                                constraints.maxHeight >= 620;
                            if (isWide) {
                              final leftUpperFlex =
                                  (100 * panelScale).round().clamp(80, 160);
                              final leftLowerFlex =
                                  (92 * panelScale).round().clamp(76, 148);
                              final rightUpperFlex =
                                  (120 * panelScale).round().clamp(92, 188);
                              final rightLowerFlex =
                                  (86 * panelScale).round().clamp(70, 140);
                              return Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          flex: leftUpperFlex,
                                          child: _ClockPanel(
                                            controller: controller,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                        SizedBox(height: panelGap),
                                        Expanded(
                                          flex: leftLowerFlex,
                                          child: _SubjectPanel(
                                            controller: controller,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: panelGap),
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          flex: rightUpperFlex,
                                          child: _AllExamsPanel(
                                            exams: controller.exams,
                                            now: controller.now,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                        SizedBox(height: panelGap),
                                        Expanded(
                                          flex: rightLowerFlex,
                                          child: _ProgressPanel(
                                            controller: controller,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                Expanded(
                                  flex: (108 * panelScale).round().clamp(82, 170),
                                  child: _ClockPanel(
                                    controller: controller,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                SizedBox(height: panelGap),
                                Expanded(
                                  flex: (94 * panelScale).round().clamp(78, 150),
                                  child: _SubjectPanel(
                                    controller: controller,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                SizedBox(height: panelGap),
                                Expanded(
                                  flex: (116 * panelScale).round().clamp(90, 186),
                                  child: _AllExamsPanel(
                                    exams: controller.exams,
                                    now: controller.now,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                SizedBox(height: panelGap),
                                Expanded(
                                  flex: (86 * panelScale).round().clamp(68, 136),
                                  child: _ProgressPanel(
                                    controller: controller,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_activeReminder != null)
                  Positioned.fill(
                    child: _ReminderOverlay(payload: _activeReminder!),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _overlayVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_overlayVisible,
                      child: _ControlCapsules(
                        holdProgress:
                            _holdElapsed.inMilliseconds /
                            _exitHoldTarget.inMilliseconds,
                        settingsHoldProgress:
                            _settingsHoldElapsed.inMilliseconds /
                            _exitHoldTarget.inMilliseconds,
                        onExitHoldStart: _startExitHold,
                        onExitHoldCancel: _cancelExitHold,
                        onSettingsHoldStart: _startSettingsHold,
                        onSettingsHoldCancel: _cancelSettingsHold,
                      ),
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

class _TopInfoBar extends StatelessWidget {
  const _TopInfoBar({
    required this.examTitle,
    required this.examInfo,
    required this.roomLabel,
    required this.fontScale,
    required this.compact,
  });

  final String examTitle;
  final String examInfo;
  final String roomLabel;
  final double fontScale;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            examTitle,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: (26 * fontScale).clamp(14, 40),
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '考试信息: $examInfo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: (18 * fontScale).clamp(11, 28),
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '试室号: $roomLabel',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: (18 * fontScale).clamp(11, 28),
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                examTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: (28 * fontScale).clamp(16, 44),
                  fontWeight: FontWeight.w800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '考试信息: $examInfo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: (20 * fontScale).clamp(12, 32),
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '试室号: $roomLabel',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: (24 * fontScale).clamp(16, 40),
            fontWeight: FontWeight.w800,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ClockPanel extends StatelessWidget {
  const _ClockPanel({required this.controller, required this.fontScale});

  final TimerController controller;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.elevated,
      padding: EdgeInsets.all((20 * fontScale).clamp(12, 34).toDouble()),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final adaptive =
              math.min(constraints.maxWidth, constraints.maxHeight) *
              0.44 *
              fontScale;
          final fontSize = adaptive.clamp(34, 220).toDouble();

          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                controller.formatClock(),
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SubjectPanel extends StatelessWidget {
  const _SubjectPanel({required this.controller, required this.fontScale});

  final TimerController controller;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final isNearEnd = controller.isNearEnd;
    final scheme = Theme.of(context).colorScheme;
    final textColor = isNearEnd ? Colors.red : scheme.onSurface;
    final activeExam = controller.activeExam;

    return SurfaceCard(
      style: isNearEnd ? SurfaceCardStyle.elevated : SurfaceCardStyle.filled,
      padding: EdgeInsets.all((20 * fontScale).clamp(12, 34).toDouble()),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final baseTitleSize =
              (math.min(constraints.maxWidth, constraints.maxHeight) * 0.18)
                  .clamp(26, 72)
                  .toDouble();
          final titleSize = baseTitleSize * fontScale;
          final countdownSize = (titleSize * 0.7).clamp(22, 64).toDouble();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前科目',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: (18 * fontScale).clamp(12, 30),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        controller.subjectLabel,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: isNearEnd ? titleSize + 10 : titleSize,
                          fontWeight: FontWeight.w900,
                          color: textColor,
                        ),
                      ),
                      // 显示材料列表
                      if (activeExam != null && activeExam.materials.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(
                            children: [
                              Container(
                                width: 1.5,
                                height: 16,
                                color: scheme.outline.withValues(alpha: 0.3),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final material in activeExam.materials)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            scheme.primaryContainer
                                                .withValues(alpha: 0.4),
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                          color: scheme.primary
                                              .withValues(alpha: 0.4),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        material.toDisplayString(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                          fontSize: (11 * fontScale)
                                              .clamp(7, 16),
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '倒计时',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: (18 * fontScale).clamp(12, 30),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                controller.formatCountdown(),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontSize: isNearEnd ? countdownSize + 8 : countdownSize,
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AllExamsPanel extends StatelessWidget {
  const _AllExamsPanel({
    required this.exams,
    required this.now,
    required this.fontScale,
  });

  final List<ExamSlot> exams;
  final DateTime now;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      style: SurfaceCardStyle.filled,
      padding: EdgeInsets.all((16 * fontScale).clamp(10, 28).toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '全部科目',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: (20 * fontScale).clamp(12, 34),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _AutoScrollExamList(
              exams: exams,
              now: now,
              fontScale: fontScale,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoScrollExamList extends StatefulWidget {
  const _AutoScrollExamList({
    required this.exams,
    required this.now,
    required this.fontScale,
  });

  final List<ExamSlot> exams;
  final DateTime now;
  final double fontScale;

  @override
  State<_AutoScrollExamList> createState() => _AutoScrollExamListState();
}

class _AutoScrollExamListState extends State<_AutoScrollExamList> {
  final ScrollController _scrollController = ScrollController();
  bool _running = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollLoop();
    });
  }

  @override
  void dispose() {
    _running = false;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _autoScrollLoop() async {
    while (mounted && _running) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || !_scrollController.hasClients) {
        continue;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) {
        continue;
      }

      final seconds = math.max(6, (maxExtent / 40).round());
      try {
        await _scrollController.animateTo(
          maxExtent,
          duration: Duration(seconds: seconds),
          curve: Curves.linear,
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted || !_scrollController.hasClients) {
          continue;
        }
        await _scrollController.animateTo(
          0,
          duration: Duration(seconds: seconds),
          curve: Curves.linear,
        );
      } catch (_) {
        // Ignore if controller gets detached while animating.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exams.isEmpty) {
      return Center(
        child: Text('暂无考试', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    final titleSize = (18 * widget.fontScale).clamp(12, 30).toDouble();
    final subtitleSize = (15 * widget.fontScale).clamp(10, 24).toDouble();

    return ListView.separated(
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.exams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final exam = widget.exams[index];
        final state = exam.stateAt(widget.now);
        final stateText = switch (state) {
          ExamState.active => '进行中',
          ExamState.upcoming => '未开始',
          ExamState.done => '已结束',
        };
        final stateColor = switch (state) {
          ExamState.active => Colors.red,
          ExamState.upcoming => Theme.of(context).colorScheme.primary,
          ExamState.done => Theme.of(context).colorScheme.outline,
        };

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.subject,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      exam.windowText(),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontSize: subtitleSize),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                stateText,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: stateColor,
                  fontWeight: FontWeight.w700,
                  fontSize: subtitleSize,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.controller, required this.fontScale});

  final TimerController controller;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final activeExam = controller.activeExam;
    final nextExam = controller.nextExam;

    return SurfaceCard(
      style: SurfaceCardStyle.filled,
      padding: EdgeInsets.all((16 * fontScale).clamp(10, 28).toDouble()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '进度',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: (20 * fontScale).clamp(12, 34),
            ),
          ),
          const SizedBox(height: 10),
          if (activeExam != null)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${(controller.progress * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: (52 * fontScale).clamp(24, 88),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AeternaTokens.superRadius,
                    ),
                    child: LinearProgressIndicator(
                      minHeight: AeternaTokens.wideProgressHeight,
                      value: controller.progress,
                    ),
                  ),
                ],
              ),
            )
          else if (nextExam != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '下一场: ${nextExam.subject}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: (20 * fontScale).clamp(12, 34),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '开始倒计时 ${controller.formatCountdown()}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: (16 * fontScale).clamp(10, 24),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Theme.of(context).colorScheme.primary,
                      size: (38 * fontScale).clamp(24, 54),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '今日考试已全部结束',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ControlCapsules extends StatelessWidget {
  const _ControlCapsules({
    required this.holdProgress,
    required this.settingsHoldProgress,
    required this.onExitHoldStart,
    required this.onExitHoldCancel,
    required this.onSettingsHoldStart,
    required this.onSettingsHoldCancel,
  });

  final double holdProgress;
  final double settingsHoldProgress;
  final VoidCallback onExitHoldStart;
  final VoidCallback onExitHoldCancel;
  final VoidCallback onSettingsHoldStart;
  final VoidCallback onSettingsHoldCancel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _HoldCircleButton(
          icon: Icons.logout,
          tooltip: '长按5秒退出',
          progress: holdProgress.clamp(0, 1).toDouble(),
          accentColor: Theme.of(context).colorScheme.error,
          onHoldStart: onExitHoldStart,
          onHoldCancel: onExitHoldCancel,
        ),
        _HoldCircleButton(
          icon: Icons.tune,
          tooltip: '长按5秒打开设置',
          progress: settingsHoldProgress.clamp(0, 1).toDouble(),
          accentColor: Theme.of(context).colorScheme.primary,
          onHoldStart: onSettingsHoldStart,
          onHoldCancel: onSettingsHoldCancel,
        ),
      ],
    );
  }
}

class _HoldCircleButton extends StatelessWidget {
  const _HoldCircleButton({
    required this.icon,
    required this.tooltip,
    required this.progress,
    required this.accentColor,
    required this.onHoldStart,
    required this.onHoldCancel,
  });

  final IconData icon;
  final String tooltip;
  final double progress;
  final Color accentColor;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldCancel;

  @override
  Widget build(BuildContext context) {
    final shortest = math.min(
      MediaQuery.sizeOf(context).width,
      MediaQuery.sizeOf(context).height,
    );
    final iconSize = (shortest * 0.026).clamp(14.0, 22.0).toDouble();
    final scheme = Theme.of(context).colorScheme;
    final p = progress.clamp(0, 1).toDouble();

    return Listener(
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldCancel(),
      behavior: HitTestBehavior.opaque,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          scale: p > 0 ? 0.96 : 1.0,
          child: SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: p > 0 ? 0.35 : 0.12),
                      blurRadius: p > 0 ? 16 : 8,
                      spreadRadius: p > 0 ? 1 : 0,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 4,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    accentColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              SizedBox(
                width: 78,
                height: 78,
                child: CircularProgressIndicator(
                  value: p,
                  strokeWidth: 4,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
              Tooltip(
                message: tooltip,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primaryContainer,
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.6),
                      width: 1.6,
                    ),
                  ),
                  child: Icon(icon, size: iconSize),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _ReminderPayload {
  const _ReminderPayload({
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final String title;
  final String subtitle;
  final Color color;
}

class _ReminderOverlay extends StatelessWidget {
  const _ReminderOverlay({required this.payload});

  final _ReminderPayload payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortest = math.min(constraints.maxWidth, constraints.maxHeight);
          final iconSize = (shortest * 0.16).clamp(52.0, 120.0).toDouble();
          final titleSize = (shortest * 0.09).clamp(28.0, 72.0).toDouble();
          final subtitleSize = (shortest * 0.055).clamp(18.0, 42.0).toDouble();

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.9, end: 1.0),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notification_important,
                      color: payload.color,
                      size: iconSize,
                    ),
                    SizedBox(height: (shortest * 0.025).clamp(10.0, 22.0)),
                    Text(
                      payload.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Colors.white,
                        fontSize: titleSize,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: (shortest * 0.02).clamp(8.0, 18.0)),
                    Text(
                      payload.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: payload.color,
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
