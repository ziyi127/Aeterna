import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({super.key});

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  static const Duration _overlayVisibleDuration = Duration(seconds: 3);
  static const Duration _exitHoldTarget = Duration(seconds: 5);
  static const Duration _reminderShowDuration = Duration(seconds: 4);

  DisplaySettings _settings = const DisplaySettings(
    fontScale: 1.0,
    roomLabel: '试室 A01',
  );
  bool _overlayVisible = true;
  bool _isHoldingExit = false;
  Duration _holdElapsed = Duration.zero;

  Timer? _overlayTimer;
  Timer? _exitHoldTimer;
  Timer? _reminderTimer;

  bool _enteredFullscreen = false;
  bool _wasFullscreen = false;
  bool _wasAlwaysOnTop = false;
  bool _enteredAlwaysOnTop = false;

  TimerController? _boundController;
  final Set<String> _firedReminderKeys = <String>{};
  final Queue<_ReminderPayload> _reminderQueue = Queue<_ReminderPayload>();
  _ReminderPayload? _activeReminder;

  @override
  void initState() {
    super.initState();
    _enterPresentationMode();
    _loadDisplaySettings();
    _showControlsTemporarily();
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
    _reminderTimer?.cancel();
    _leavePresentationMode();
    super.dispose();
  }

  void _onControllerTick() {
    _checkReminderMoments();
  }

  Future<void> _enterPresentationMode() async {
    try {
      _wasFullscreen = await windowManager.isFullScreen();
      if (!_wasFullscreen) {
        await windowManager.setFullScreen(true);
        _enteredFullscreen = true;
      }

      // Windows only: simulate uiAccess-like presentation lock by forcing
      // top-most + focus while monitor page is active.
      if (Platform.isWindows) {
        _wasAlwaysOnTop = await windowManager.isAlwaysOnTop();
        if (!_wasAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(true);
          _enteredAlwaysOnTop = true;
        }
        await windowManager.focus();
      }
    } catch (_) {
      // Ignore unsupported platforms.
    }
  }

  Future<void> _leavePresentationMode() async {
    try {
      if (Platform.isWindows && _enteredAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(false);
        _enteredAlwaysOnTop = false;
      }
      if (_enteredFullscreen) {
        await windowManager.setFullScreen(false);
      }
    } catch (_) {
      // Ignore unsupported platforms.
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
    setState(() => _overlayVisible = true);
    _overlayTimer?.cancel();
    _overlayTimer = Timer(_overlayVisibleDuration, () {
      if (!mounted || _isHoldingExit) {
        return;
      }
      setState(() => _overlayVisible = false);
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
                      DisplaySettings(
                        fontScale: localScale,
                        roomLabel: _settings.roomLabel,
                      ),
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

    _showNextReminderIfIdle();
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

    return Listener(
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
                        currentExam:
                            controller.activeExam?.subject ?? '当前无进行中考试',
                        roomLabel: _settings.roomLabel,
                        fontScale: _settings.fontScale,
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 1200;
                            if (isWide) {
                              return Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _ClockPanel(
                                            controller: controller,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Expanded(
                                          child: _SubjectPanel(
                                            controller: controller,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    flex: 2,
                                    child: Column(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _AllExamsPanel(
                                            exams: controller.exams,
                                            now: controller.now,
                                            fontScale: _settings.fontScale,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Expanded(
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
                                  child: _ClockPanel(
                                    controller: controller,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _SubjectPanel(
                                    controller: controller,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _AllExamsPanel(
                                    exams: controller.exams,
                                    now: controller.now,
                                    fontScale: _settings.fontScale,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
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
                  right: 24,
                  bottom: 24,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _overlayVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_overlayVisible,
                      child: _ControlCapsules(
                        holdProgress:
                            _holdElapsed.inMilliseconds /
                            _exitHoldTarget.inMilliseconds,
                        onExitHoldStart: _startExitHold,
                        onExitHoldCancel: _cancelExitHold,
                        onOpenSettings: _openDisplaySettingsDialog,
                      ),
                    ),
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

class _TopInfoBar extends StatelessWidget {
  const _TopInfoBar({
    required this.examTitle,
    required this.currentExam,
    required this.roomLabel,
    required this.fontScale,
  });

  final String examTitle;
  final String currentExam;
  final String roomLabel;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
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
                '当前科目: $currentExam',
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
      padding: const EdgeInsets.all(20),
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

    return SurfaceCard(
      style: isNearEnd ? SurfaceCardStyle.elevated : SurfaceCardStyle.filled,
      padding: const EdgeInsets.all(20),
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
                  child: Text(
                    controller.subjectLabel,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: isNearEnd ? titleSize + 10 : titleSize,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                    ),
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
      padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
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
    required this.onExitHoldStart,
    required this.onExitHoldCancel,
    required this.onOpenSettings,
  });

  final double holdProgress;
  final VoidCallback onExitHoldStart;
  final VoidCallback onExitHoldCancel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final clampedProgress = holdProgress.clamp(0, 1).toDouble();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTapDown: (_) => onExitHoldStart(),
          onTapUp: (_) => onExitHoldCancel(),
          onTapCancel: onExitHoldCancel,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: clampedProgress,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  clampedProgress <= 0
                      ? '长按5秒退出'
                      : '退出中 ${(clampedProgress * 5).toStringAsFixed(1)} / 5.0s',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onOpenSettings,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune),
                  const SizedBox(width: 8),
                  Text(
                    '设置',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      child: Center(
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
                size: 120,
              ),
              const SizedBox(height: 22),
              Text(
                payload.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 72,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                payload.subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: payload.color,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
