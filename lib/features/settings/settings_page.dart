import 'dart:async';

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/exit_password_dialog.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/app_theme.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

enum _LeaveAction { save, discard, cancel }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.currentThemeMode,
    required this.currentThemePalette,
    required this.onThemeChanged,
  });

  final ThemeMode currentThemeMode;
  final ThemePalette currentThemePalette;
  final Future<void> Function({
    required ThemeMode mode,
    required ThemePalette palette,
  })
  onThemeChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _ntpController;
  late final TextEditingController _roomController;
  bool _seededFromState = false;
  double _fontScale = 1.0;
  bool _saving = false;
  bool _syncingNow = false;
  bool _themeUpdating = false;
  int _maxDriftStepMs = 250;
  String _initialNtp = '';
  String _initialRoom = '试室 A01';
  double _initialFontScale = 1.0;
  int _initialMaxDriftStepMs = 250;
  Timer? _autoSaveDebounce;
  ThemeMode _themeMode = ThemeMode.system;
  ThemePalette _themePalette = ThemePalette.emerald;
  ThemeMode _initialThemeMode = ThemeMode.system;
  ThemePalette _initialThemePalette = ThemePalette.emerald;
  TimeSourceMode _lastModeHint = TimeSourceMode.offlineManual;
  bool _exitPasswordEnabled = false;
  bool _safeMode = false;
  String _exitPassword = '';
  bool _initialExitPasswordEnabled = false;
  bool _initialSafeMode = false;
  String _initialExitPassword = '';

  @override
  void initState() {
    super.initState();
    _ntpController = TextEditingController();
    _roomController = TextEditingController();
    _themeMode = widget.currentThemeMode;
    _themePalette = widget.currentThemePalette;
    _initialThemeMode = widget.currentThemeMode;
    _initialThemePalette = widget.currentThemePalette;
    _loadDisplaySettings();
    _ntpController.addListener(() {
      if (!_seededFromState || !mounted) {
        return;
      }
      _scheduleAutoSave(() {
        final controller = TimerScope.of(context);
        _saveSyncSettings(controller);
      });
    });
    _roomController.addListener(() {
      if (!mounted) {
        return;
      }
      _scheduleAutoSave(_saveDisplaySettings);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededFromState) {
      return;
    }
    _ntpController.text = TimerScope.of(context).ntpAddress;
    _initialNtp = _ntpController.text;
    _lastModeHint = TimerScope.of(context).mode;
    _maxDriftStepMs = TimerScope.of(context).maxDriftStepMs;
    _initialMaxDriftStepMs = _maxDriftStepMs;
    _seededFromState = true;
  }

  @override
  void dispose() {
    _autoSaveDebounce?.cancel();
    _ntpController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  void _scheduleAutoSave(FutureOr<void> Function() action) {
    _autoSaveDebounce?.cancel();
    _autoSaveDebounce = Timer(const Duration(milliseconds: 480), () {
      unawaited(Future<void>.value(action()));
    });
  }

  Future<void> _loadDisplaySettings() async {
    final settings = await ConfigManager.loadDisplaySettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _roomController.text = settings.roomLabel;
      _fontScale = settings.fontScale;
      _initialRoom = settings.roomLabel;
      _initialFontScale = settings.fontScale;
      _maxDriftStepMs = settings.maxDriftStepMs;
      _initialMaxDriftStepMs = settings.maxDriftStepMs;
      _themeMode = _themeModeFromKey(settings.themeMode);
      _themePalette = ThemePaletteLabel.fromKey(settings.themePalette);
      _initialThemeMode = _themeMode;
      _initialThemePalette = _themePalette;
      _exitPasswordEnabled = settings.exitPasswordEnabled;
      _safeMode = settings.safeMode;
      _exitPassword = settings.exitPassword;
      _initialExitPasswordEnabled = settings.exitPasswordEnabled;
      _initialSafeMode = settings.safeMode;
      _initialExitPassword = settings.exitPassword;
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

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return '浅色';
      case ThemeMode.dark:
        return '深色';
      case ThemeMode.system:
        return '跟随系统';
    }
  }

  bool get _displayDirty {
    return _roomController.text.trim() != _initialRoom ||
        (_fontScale - _initialFontScale).abs() > 0.0001 ||
        _maxDriftStepMs != _initialMaxDriftStepMs ||
        _themeMode != _initialThemeMode ||
      _themePalette != _initialThemePalette ||
      _exitPasswordEnabled != _initialExitPasswordEnabled ||
      _safeMode != _initialSafeMode ||
      _exitPassword != _initialExitPassword;
  }

  bool get _syncDirty => _ntpController.text.trim() != _initialNtp;

  bool _hasUnsavedChanges() => _displayDirty || _syncDirty;

  bool _canSaveAll(TimerController controller) {
    return _hasUnsavedChanges() &&
        !_saving &&
        !_syncingNow &&
        !_themeUpdating &&
        !controller.isSyncing;
  }

  bool _canSaveSyncOnly(TimerController controller) {
    return _syncDirty && !_saving && !_syncingNow && !controller.isSyncing;
  }

  bool _canSaveDisplayOnly(TimerController controller) {
    return _displayDirty &&
        !_saving &&
        !_syncingNow &&
        !_themeUpdating &&
        !controller.isSyncing;
  }

  Future<bool> _onWillPop(TimerController controller) async {
    if (!_hasUnsavedChanges()) {
      return true;
    }
    final action = await showDialog<_LeaveAction>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('有未保存更改'),
          content: const Text('你有未保存的设置。离开前是否保存？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(_LeaveAction.cancel),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(_LeaveAction.discard),
              child: const Text('放弃'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(_LeaveAction.save),
              child: const Text('保存并离开'),
            ),
          ],
        );
      },
    );
    if (action == _LeaveAction.save) {
      await _saveAll(controller);
      return true;
    }
    return action == _LeaveAction.discard;
  }

  Future<void> _handleBackAttempt(TimerController controller) async {
    final shouldPop = await _onWillPop(controller);
    if (!mounted || !shouldPop) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _saveDisplaySettings() async {
    final room = _roomController.text.trim();
    await ConfigManager.saveDisplaySettings(
      DisplaySettings(
        fontScale: _fontScale,
        roomLabel: room.isEmpty ? '试室 A01' : room,
        themeMode: _themeModeKey(_themeMode),
        themePalette: _themePalette.key,
        maxDriftStepMs: _maxDriftStepMs,
        exitPasswordEnabled: _exitPasswordEnabled,
        exitPassword: _exitPassword,
        safeMode: _safeMode,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _initialRoom = room.isEmpty ? '试室 A01' : room;
      _initialFontScale = _fontScale;
      _initialMaxDriftStepMs = _maxDriftStepMs;
      _initialThemeMode = _themeMode;
      _initialThemePalette = _themePalette;
      _initialExitPasswordEnabled = _exitPasswordEnabled;
      _initialSafeMode = _safeMode;
      _initialExitPassword = _exitPassword;
    });
  }

  Future<void> _setOrChangeExitPassword() async {
    final password = await ExitPasswordDialog.show(context);
    if (password == null) {
      return;
    }
    if (!RegExp(r'^\d{1,6}$').hasMatch(password)) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('密码必须是 1-6 位数字')));
      return;
    }
    setState(() {
      _exitPassword = password;
      _exitPasswordEnabled = true;
    });
    _scheduleAutoSave(_saveDisplaySettings);
  }

  Future<void> _applyTheme({ThemeMode? mode, ThemePalette? palette}) async {
    final nextMode = mode ?? _themeMode;
    final nextPalette = palette ?? _themePalette;
    if (_themeUpdating) {
      return;
    }
    if (nextMode == _themeMode && nextPalette == _themePalette) {
      return;
    }
    setState(() {
      _themeUpdating = true;
      _themeMode = nextMode;
      _themePalette = nextPalette;
    });
    try {
      await widget.onThemeChanged(mode: nextMode, palette: nextPalette);
      if (!mounted) {
        return;
      }
      setState(() {
        _initialThemeMode = nextMode;
        _initialThemePalette = nextPalette;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已切换主题: ${nextPalette.label} / ${_themeModeLabel(nextMode)}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _themeUpdating = false);
      }
    }
  }

  void _saveSyncSettings(TimerController controller) {
    controller.setNtpAddress(_ntpController.text);
    controller.setMode(_lastModeHint);
    controller.setMaxDriftStepMs(_maxDriftStepMs);
    _initialNtp = _ntpController.text.trim();
    ConfigManager.saveSyncSettings(
      SyncSettings(
        ntpAddress: _initialNtp,
        modeKey: _lastModeHint.key,
        maxDriftStepMs: _maxDriftStepMs,
      ),
    );
  }

  Future<void> _saveAll(TimerController controller) async {
    if (!_hasUnsavedChanges()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有需要保存的更改')));
      return;
    }
    if (_saving || _syncingNow || controller.isSyncing) {
      return;
    }
    setState(() => _saving = true);
    try {
      _saveSyncSettings(controller);
      await _saveDisplaySettings();
      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('设置已保存')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _syncNow(TimerController controller) async {
    if (_syncingNow) {
      return;
    }
    setState(() => _syncingNow = true);
    try {
      _saveSyncSettings(controller);
      await controller.syncNow();
      if (!mounted) {
        return;
      }
      final isFailure = controller.syncState == SyncState.failure;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isFailure ? '同步失败，请检查网络或地址' : '同步完成')),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingNow = false);
      }
    }
  }

  IconData _syncIcon(SyncState state) {
    return switch (state) {
      SyncState.idle => Icons.pause_circle_outline,
      SyncState.syncing => Icons.sync,
      SyncState.success => Icons.check_circle_outline,
      SyncState.failure => Icons.error_outline,
    };
  }

  Color _syncColor(BuildContext context, SyncState state) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      SyncState.idle => scheme.outline,
      SyncState.syncing => scheme.primary,
      SyncState.success => Colors.green,
      SyncState.failure => scheme.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = TimerScope.of(context);
    final syncAt = controller.lastSyncAt;
    final width = MediaQuery.sizeOf(context).width;
    final hasDirty = _hasUnsavedChanges();
    final syncColor = _syncColor(context, controller.syncState);
    final syncText = controller.syncState == SyncState.failure
        ? '${controller.syncStatus} (${controller.syncErrorMessage})'
        : controller.syncStatus;
    final syncing = _syncingNow || controller.isSyncing;

    return PopScope<void>(
      canPop: !hasDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBackAttempt(controller));
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('系统设置 Settings'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: FilledButton.icon(
                  onPressed: _canSaveAll(controller)
                      ? () => _saveAll(controller)
                      : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中' : '保存全部'),
                ),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: AeternaTokens.pagePaddingFor(width),
          child: ListView(
            children: [
              SurfaceCard(
                style: SurfaceCardStyle.elevated,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.schedule_outlined),
                        const SizedBox(width: 8),
                        Text(
                          '时间同步',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        if (_syncDirty) const Chip(label: Text('未保存')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '配置 NTP 地址与时间源。建议先保存，再执行立即同步。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ntpController,
                      onChanged: (_) {
                        _scheduleAutoSave(() async {
                          _saveSyncSettings(controller);
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'NTP 地址',
                        hintText: '例如: pool.ntp.org 或 192.168.1.2',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<TimeSourceMode>(
                        segments: TimeSourceMode.values
                            .map(
                              (mode) => ButtonSegment<TimeSourceMode>(
                                value: mode,
                                label: Text(mode.label),
                              ),
                            )
                            .toList(),
                        selected: {controller.mode},
                        onSelectionChanged: (selection) {
                          final newMode = selection.first;
                          if (newMode == controller.mode) {
                            return;
                          }
                          controller.setMode(newMode);
                          if (_lastModeHint == newMode) {
                            return;
                          }
                          _lastModeHint = newMode;
                          _scheduleAutoSave(() async {
                            _saveSyncSettings(controller);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('已切换到 ${newMode.label}，建议立即同步'),
                              action: newMode == TimeSourceMode.offlineManual
                                  ? null
                                  : SnackBarAction(
                                      label: '立即同步',
                                      onPressed: () => _syncNow(controller),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: syncColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: syncColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _syncIcon(controller.syncState),
                            color: syncColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '同步状态: $syncText',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      syncAt == null
                          ? '最近同步: 尚未同步'
                          : '最近同步: ${syncAt.hour.toString().padLeft(2, '0')}:${syncAt.minute.toString().padLeft(2, '0')}:${syncAt.second.toString().padLeft(2, '0')}',
                    ),
                    const SizedBox(height: 10),
                    Text('漂移校正步长: ${_maxDriftStepMs}ms/次'),
                    Slider(
                      min: 20,
                      max: 1000,
                      divisions: 49,
                      value: _maxDriftStepMs.toDouble(),
                      label: '${_maxDriftStepMs}ms',
                      onChanged: (value) {
                        setState(() => _maxDriftStepMs = value.round());
                        controller.setMaxDriftStepMs(_maxDriftStepMs);
                        _scheduleAutoSave(() async {
                          _saveSyncSettings(controller);
                        });
                      },
                    ),
                    Text(
                      '当前时钟偏移: ${controller.currentOffsetMs}ms  |  最近一次校正: ${controller.lastAppliedDriftMs}ms',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: syncing
                              ? null
                              : () => _syncNow(controller),
                          icon: syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: Text(syncing ? '同步中' : '立即同步'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _canSaveSyncOnly(controller)
                              ? () {
                                  _saveSyncSettings(controller);
                                  FocusScope.of(context).unfocus();
                                  setState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('同步设置已保存')),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.save_alt_outlined),
                          label: const Text('仅保存同步'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SurfaceCard(
                style: SurfaceCardStyle.elevated,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.slideshow_outlined),
                        const SizedBox(width: 8),
                        Text(
                          '放映参数',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        if (_displayDirty) const Chip(label: Text('未保存')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '这里设置试室号与字号倍率。放映页会实时读取此配置。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _roomController,
                      onChanged: (_) {
                        _scheduleAutoSave(_saveDisplaySettings);
                      },
                      decoration: const InputDecoration(
                        labelText: '试室号',
                        hintText: '例如 A201 / 第3试室',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('字体大小倍率: ${_fontScale.toStringAsFixed(2)}x'),
                    Slider(
                      min: 0.7,
                      max: 1.8,
                      divisions: 11,
                      value: _fontScale,
                      onChanged: (value) {
                        setState(() => _fontScale = value);
                        _scheduleAutoSave(_saveDisplaySettings);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '预览字号: 恒时 Aeterna',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: (20 * _fontScale).clamp(14, 40),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _canSaveDisplayOnly(controller)
                          ? () async {
                              await _saveDisplaySettings();
                              if (!context.mounted) {
                                return;
                              }
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('放映参数已保存')),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.save_alt_outlined),
                      label: const Text('仅保存放映参数'),
                    ),
                    const SizedBox(height: 18),
                    Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '放映安全',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '可设置退出密码。开启安全模式后，考试进行中会自动临时关闭密码保护。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用退出密码'),
                      subtitle: Text(
                        _exitPassword.isEmpty ? '未设置密码' : '已设置 ${_exitPassword.length} 位数字密码',
                      ),
                      value: _exitPasswordEnabled,
                      onChanged: (enabled) {
                        setState(() {
                          _exitPasswordEnabled = enabled;
                          if (!enabled) {
                            _safeMode = false;
                          }
                        });
                        _scheduleAutoSave(_saveDisplaySettings);
                      },
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _setOrChangeExitPassword,
                          icon: const Icon(Icons.pin_outlined),
                          label: Text(_exitPassword.isEmpty ? '设置密码' : '修改密码'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exitPassword.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _exitPassword = '';
                                    _exitPasswordEnabled = false;
                                    _safeMode = false;
                                  });
                                  _scheduleAutoSave(_saveDisplaySettings);
                                },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除密码'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('安全模式'),
                      subtitle: const Text('考试进行中：退出放映无需输入密码；考试结束后自动恢复密码'),
                      value: _safeMode,
                      onChanged: _exitPasswordEnabled
                          ? (enabled) {
                              setState(() => _safeMode = enabled);
                              _scheduleAutoSave(_saveDisplaySettings);
                            }
                          : null,
                    ),
                    const SizedBox(height: 18),
                    Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '主题外观',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '配色和明暗会立即生效。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            label: Text('系统'),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            label: Text('浅色'),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            label: Text('深色'),
                          ),
                        ],
                        selected: {_themeMode},
                        onSelectionChanged: _themeUpdating
                            ? null
                            : (selection) => _applyTheme(mode: selection.first),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<ThemePalette>(
                        segments: ThemePalette.values
                            .map(
                              (palette) => ButtonSegment<ThemePalette>(
                                value: palette,
                                label: Text(palette.label),
                              ),
                            )
                            .toList(),
                        selected: {_themePalette},
                        onSelectionChanged: _themeUpdating
                            ? null
                            : (selection) =>
                                  _applyTheme(palette: selection.first),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
