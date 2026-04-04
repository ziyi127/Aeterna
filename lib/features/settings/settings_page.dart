import 'dart:async';
import 'dart:math';

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/security/f2a_totp.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/aeterna_reveal.dart';
import 'package:aeterna/shared/widgets/exit_password_dialog.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/app_theme.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LeaveAction { save, discard, cancel }
enum _ExitProtectionMode { none, localPassword, f2a }
enum _F2AEnrollmentMode { webPage, authenticatorApp }

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
  int _manualOffsetMs = 0;
  bool _autoSyncEnabled = true;
  int _autoSyncIntervalMinutes = 5;
  String _initialNtp = '';
  String _initialRoom = '试室 A01';
  double _initialFontScale = 1.0;
  int _initialManualOffsetMs = 0;
  bool _initialAutoSyncEnabled = true;
  int _initialAutoSyncIntervalMinutes = 5;
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
  bool _f2aEnabled = false;
  bool _initialF2aEnabled = false;
  List<F2AFactor> _f2aFactors = const [];
  String _initialF2aSignature = '';

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
    _ntpController.text = TimerScope.of(context).ntpServers.join('\n');
    _initialNtp = _ntpController.text;
    _lastModeHint = TimerScope.of(context).mode;
    _manualOffsetMs = TimerScope.of(context).manualOffsetMs;
    _initialManualOffsetMs = _manualOffsetMs;
    _autoSyncEnabled = TimerScope.of(context).autoSyncEnabled;
    _initialAutoSyncEnabled = _autoSyncEnabled;
    _autoSyncIntervalMinutes = TimerScope.of(context).autoSyncIntervalMinutes;
    _initialAutoSyncIntervalMinutes = _autoSyncIntervalMinutes;
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
      _f2aEnabled = settings.f2aEnabled;
      _initialF2aEnabled = settings.f2aEnabled;
      _f2aFactors = settings.f2aFactors;
      _initialF2aSignature = _f2aSignature(settings.f2aFactors);
    });
  }

  String _f2aSignature(List<F2AFactor> factors) {
    return factors
        .map((e) => '${e.id}|${e.name}|${e.secret}|${e.createdAtMs}')
        .join('::');
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
        return '系统';
    }
  }

  _ExitProtectionMode get _exitProtectionMode {
    if (_f2aEnabled) {
      return _ExitProtectionMode.f2a;
    }
    if (_exitPasswordEnabled) {
      return _ExitProtectionMode.localPassword;
    }
    return _ExitProtectionMode.none;
  }

  Future<void> _setExitProtectionMode(_ExitProtectionMode mode) async {
    if (!mounted) {
      return;
    }
    switch (mode) {
      case _ExitProtectionMode.none:
        setState(() {
          _exitPasswordEnabled = false;
          _safeMode = false;
          _f2aEnabled = false;
        });
        _scheduleAutoSave(_saveDisplaySettings);
        return;
      case _ExitProtectionMode.localPassword:
        if (_exitPassword.isEmpty) {
          await _setOrChangeExitPassword();
          if (!mounted) {
            return;
          }
          if (_exitPassword.isEmpty) {
            return;
          }
        }
        setState(() {
          _exitPasswordEnabled = true;
          _safeMode = false;
          _f2aEnabled = false;
        });
        _scheduleAutoSave(_saveDisplaySettings);
        return;
      case _ExitProtectionMode.f2a:
        if (_f2aFactors.isEmpty) {
          await _enrollF2aFactor();
          if (!mounted || !_f2aEnabled) {
            return;
          }
        } else {
          setState(() {
            _exitPasswordEnabled = false;
            _safeMode = false;
            _f2aEnabled = true;
          });
          _scheduleAutoSave(_saveDisplaySettings);
        }
        return;
    }
  }

  bool get _displayDirty {
    return _roomController.text.trim() != _initialRoom ||
        (_fontScale - _initialFontScale).abs() > 0.0001 ||
        _themeMode != _initialThemeMode ||
      _themePalette != _initialThemePalette ||
      _exitPasswordEnabled != _initialExitPasswordEnabled ||
      _safeMode != _initialSafeMode ||
      _exitPassword != _initialExitPassword ||
      _f2aEnabled != _initialF2aEnabled ||
      _f2aSignature(_f2aFactors) != _initialF2aSignature;
  }

  bool get _syncDirty =>
      _ntpController.text.trim() != _initialNtp ||
      _manualOffsetMs != _initialManualOffsetMs ||
      _autoSyncEnabled != _initialAutoSyncEnabled ||
      _autoSyncIntervalMinutes != _initialAutoSyncIntervalMinutes;

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
        exitPasswordEnabled: _exitPasswordEnabled,
        exitPassword: _exitPassword,
        safeMode: _safeMode,
        f2aEnabled: _f2aEnabled,
        f2aFactors: _f2aFactors,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _initialRoom = room.isEmpty ? '试室 A01' : room;
      _initialFontScale = _fontScale;
      _initialThemeMode = _themeMode;
      _initialThemePalette = _themePalette;
      _initialExitPasswordEnabled = _exitPasswordEnabled;
      _initialSafeMode = _safeMode;
      _initialExitPassword = _exitPassword;
      _initialF2aEnabled = _f2aEnabled;
      _initialF2aSignature = _f2aSignature(_f2aFactors);
    });
  }

  List<String> _parseNtpServers() {
    return _ntpController.text
        .split(RegExp(r'[\n,;]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
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
      _exitPassword = ConfigManager.normalizePasswordStorage(password);
      _exitPasswordEnabled = true;
      _f2aEnabled = false;
    });
    _scheduleAutoSave(_saveDisplaySettings);
  }

  Future<bool> _confirmRotateF2a() async {
    if (_f2aFactors.isEmpty) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('重新生成 F2A 二维码'),
          content: const Text('当前已经绑定了 F2A。生成新的二维码会让旧的 F2A 失效，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续'),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<_F2AEnrollmentMode?> _chooseF2aEnrollmentMode() async {
    return showDialog<_F2AEnrollmentMode>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('选择 F2A 绑定方式'),
          content: const Text('你可以使用 Aeterna 网页绑定，或者直接使用第三方 F2A 验证器。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(_F2AEnrollmentMode.webPage),
              icon: const Icon(Icons.web_outlined),
              label: const Text('Aeterna 网页'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(ctx).pop(_F2AEnrollmentMode.authenticatorApp),
              icon: const Icon(Icons.phone_android_outlined),
              label: const Text('第三方验证器'),
            ),
          ],
        );
      },
    );
  }

  String _buildF2aPageUrl({required String secret}) {
    return Uri.https('ziyi127.github.io', '/Aeterna/tools/f2a/', {
      'entry': 'f2a',
      'secret': secret,
    }).toString();
  }

  String _buildOtpauthUri({required String secret, required String label}) {
    final encodedLabel = Uri.encodeComponent('Aeterna:$label');
    return 'otpauth://totp/$encodedLabel?secret=$secret&issuer=Aeterna&digits=6&period=30';
  }

  Future<void> _enrollF2aFactor() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(1 << 20);
    final factorId = '${now}_$random';
    final secret = F2ATotp.generateSecret(length: 32);

    final mode = await _chooseF2aEnrollmentMode();
    if (mode == null || !mounted) {
      return;
    }

    final rotateConfirmed = await _confirmRotateF2a();
    if (!rotateConfirmed || !mounted) {
      return;
    }

    setState(() {
      _f2aEnabled = false;
      _f2aFactors = const [];
    });

    final pageUrl = switch (mode) {
      _F2AEnrollmentMode.webPage => _buildF2aPageUrl(secret: secret),
      _F2AEnrollmentMode.authenticatorApp => _buildOtpauthUri(
        secret: secret,
        label: 'F2A $factorId',
      ),
    };
    final qrTitle = switch (mode) {
      _F2AEnrollmentMode.webPage => '扫码绑定 Aeterna 网页',
      _F2AEnrollmentMode.authenticatorApp => '扫码绑定第三方验证器',
    };
    final qrHint = switch (mode) {
      _F2AEnrollmentMode.webPage => '请使用手机扫码。网页会自动接收密钥并写入 Cookie。',
      _F2AEnrollmentMode.authenticatorApp => '请使用第三方 F2A 验证器扫码，扫码后会生成 6 位动态码。',
    };
    final verifyTitle = switch (mode) {
      _F2AEnrollmentMode.webPage => '验证网页验证码',
      _F2AEnrollmentMode.authenticatorApp => '验证动态验证码',
    };
    final verifyHint = switch (mode) {
      _F2AEnrollmentMode.webPage => '请输入网页验证器当前显示的 6 位验证码，确认已成功读取。',
      _F2AEnrollmentMode.authenticatorApp => '请输入第三方验证器当前显示的 6 位验证码。',
    };
    final primaryLabel = switch (mode) {
      _F2AEnrollmentMode.webPage => '验证并开启',
      _F2AEnrollmentMode.authenticatorApp => '验证并开启',
    };

    final continueSetup = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(qrTitle),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(qrHint),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AeternaTokens.radiusControl,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: QrImageView(
                      data: pageUrl,
                      size: 210,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SelectableText(
                  pageUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                if (mode == _F2AEnrollmentMode.webPage)
                  Text(
                    '网页会在首次打开时提示设置名称，并把密钥和名称一起保存到 Cookie。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (mode == _F2AEnrollmentMode.authenticatorApp)
                  Text(
                    '这是一组标准 TOTP 配置，第三方验证器会直接识别。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    launchUrl(
                      Uri.parse(pageUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('在浏览器打开绑定页'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('我已扫码'),
            ),
          ],
        );
      },
    );

    if (continueSetup != true || !mounted) {
      return;
    }

    final verifyController = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(verifyTitle),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(verifyHint),
                const SizedBox(height: 12),
                TextField(
                  controller: verifyController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '6 位验证码',
                    hintText: mode == _F2AEnrollmentMode.webPage
                        ? '来自 Aeterna 网页验证器'
                        : '来自第三方验证器',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final ok = switch (mode) {
                  _F2AEnrollmentMode.webPage => F2ATotp.verifyCode(
                      code: verifyController.text,
                      factors: [F2AFactor(id: factorId, name: 'F2A 1', secret: secret, createdAtMs: now)],
                      at: DateTime.now(),
                    ),
                  _F2AEnrollmentMode.authenticatorApp => F2ATotp.verifyCode(
                      code: verifyController.text,
                      factors: [F2AFactor(id: factorId, name: 'F2A 1', secret: secret, createdAtMs: now)],
                      at: DateTime.now(),
                    ),
                };
                if (!ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(mode == _F2AEnrollmentMode.webPage ? '验证码不正确，请确认网页当前 6 位码' : '验证码不正确，请重试')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(primaryLabel),
            ),
          ],
        );
      },
    );
    verifyController.dispose();

    if (verified != true || !mounted) {
      return;
    }

    final factor = F2AFactor(
      id: factorId,
      name: 'F2A ${_f2aFactors.length + 1}',
      secret: secret,
      createdAtMs: now,
    );
    setState(() {
      _f2aFactors = [factor];
      _f2aEnabled = true;
      _exitPasswordEnabled = false;
    });
    _scheduleAutoSave(_saveDisplaySettings);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('F2A 已启用')));
  }

  void _removeF2aFactor(String id) {
    setState(() {
      _f2aFactors = _f2aFactors.where((factor) => factor.id != id).toList();
      if (_f2aFactors.isEmpty) {
        _f2aEnabled = false;
      }
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
    final servers = _parseNtpServers();
    controller.setNtpServers(servers);
    controller.setMode(_lastModeHint);
    controller.setManualOffsetMs(_manualOffsetMs);
    controller.setAutoSyncEnabled(_autoSyncEnabled);
    controller.setAutoSyncIntervalMinutes(_autoSyncIntervalMinutes);
    _initialNtp = _ntpController.text.trim();
    _initialManualOffsetMs = _manualOffsetMs;
    _initialAutoSyncEnabled = _autoSyncEnabled;
    _initialAutoSyncIntervalMinutes = _autoSyncIntervalMinutes;
    ConfigManager.saveSyncSettings(
      SyncSettings(
        ntpServers: servers,
        modeKey: _lastModeHint.key,
        manualOffsetMs: _manualOffsetMs,
        autoSyncEnabled: _autoSyncEnabled,
        autoSyncIntervalMinutes: _autoSyncIntervalMinutes,
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
              AeternaReveal(
                delay: const Duration(milliseconds: 60),
                child: SurfaceCard(
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
                        labelText: 'NTP 服务器列表',
                        hintText: '每行一个地址，例如:\npool.ntp.org\ntime.cloudflare.com\nntp.aliyun.com',
                      ),
                      minLines: 3,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '应用只会校正 Aeterna 内部时间偏移，不会修改系统时间。',
                      style: Theme.of(context).textTheme.bodySmall,
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('自动同步'),
                      subtitle: Text(
                        _autoSyncEnabled
                            ? '每 $_autoSyncIntervalMinutes 分钟自动同步一次'
                            : '已关闭自动同步，仅手动同步',
                      ),
                      value: _autoSyncEnabled,
                      onChanged: (enabled) {
                        setState(() => _autoSyncEnabled = enabled);
                        controller.setAutoSyncEnabled(enabled);
                        _scheduleAutoSave(() async {
                          _saveSyncSettings(controller);
                        });
                      },
                    ),
                    if (_autoSyncEnabled) ...[
                      Text('自动同步间隔: $_autoSyncIntervalMinutes 分钟'),
                      Slider(
                        min: 1,
                        max: 180,
                        divisions: 179,
                        value: _autoSyncIntervalMinutes.toDouble(),
                        label: '$_autoSyncIntervalMinutes 分钟',
                        onChanged: (value) {
                          final minutes = value.round();
                          setState(() => _autoSyncIntervalMinutes = minutes);
                          controller.setAutoSyncIntervalMinutes(minutes);
                          _scheduleAutoSave(() async {
                            _saveSyncSettings(controller);
                          });
                        },
                      ),
                      const SizedBox(height: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: syncColor.withValues(alpha: 0.08),
                        borderRadius: AeternaTokens.radiusControl,
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
                    if (controller.lastSyncServer.isNotEmpty)
                      Text(
                        '最近成功服务器: ${controller.lastSyncServer}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 10),
                    Text('手动时间偏移: ${_manualOffsetMs >= 0 ? '+' : ''}${_manualOffsetMs}ms'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _manualOffsetMs -= 100);
                            controller.setManualOffsetMs(_manualOffsetMs);
                            _scheduleAutoSave(() async {
                              _saveSyncSettings(controller);
                            });
                          },
                          child: const Text('-100ms'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _manualOffsetMs -= 10);
                            controller.setManualOffsetMs(_manualOffsetMs);
                            _scheduleAutoSave(() async {
                              _saveSyncSettings(controller);
                            });
                          },
                          child: const Text('-10ms'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _manualOffsetMs += 10);
                            controller.setManualOffsetMs(_manualOffsetMs);
                            _scheduleAutoSave(() async {
                              _saveSyncSettings(controller);
                            });
                          },
                          child: const Text('+10ms'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            setState(() => _manualOffsetMs += 100);
                            controller.setManualOffsetMs(_manualOffsetMs);
                            _scheduleAutoSave(() async {
                              _saveSyncSettings(controller);
                            });
                          },
                          child: const Text('+100ms'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _manualOffsetMs = 0);
                            controller.setManualOffsetMs(0);
                            _scheduleAutoSave(() async {
                              _saveSyncSettings(controller);
                            });
                          },
                          child: const Text('重置手动偏移'),
                        ),
                      ],
                    ),
                    Text(
                      '当前总偏移: ${controller.currentOffsetMs}ms  |  网络偏移: ${controller.networkOffsetMs}ms  |  最近同步修正: ${controller.lastAppliedSyncDeltaMs}ms',
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
              ),
              const SizedBox(height: 14),
              AeternaReveal(
                delay: const Duration(milliseconds: 130),
                child: SurfaceCard(
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
                    Text(
                      '退出保护方式',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<_ExitProtectionMode>(
                      segments: const [
                        ButtonSegment<_ExitProtectionMode>(
                          value: _ExitProtectionMode.none,
                          label: Text('关闭'),
                          icon: Icon(Icons.lock_open_outlined),
                        ),
                        ButtonSegment<_ExitProtectionMode>(
                          value: _ExitProtectionMode.localPassword,
                          label: Text('本地密码'),
                          icon: Icon(Icons.pin_outlined),
                        ),
                        ButtonSegment<_ExitProtectionMode>(
                          value: _ExitProtectionMode.f2a,
                          label: Text('F2A'),
                          icon: Icon(Icons.qr_code_2_outlined),
                        ),
                      ],
                      selected: {_exitProtectionMode},
                      onSelectionChanged: (selection) {
                        unawaited(_setExitProtectionMode(selection.first));
                      },
                    ),
                    const SizedBox(height: 10),
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
                    Text(
                      _exitProtectionMode == _ExitProtectionMode.localPassword
                          ? '当前使用本地密码保护'
                          : _exitProtectionMode == _ExitProtectionMode.f2a
                              ? '当前使用 F2A 保护'
                              : '当前未启用退出保护',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('安全模式'),
                      subtitle: const Text('考试进行中：退出放映无需输入保护码；考试结束后自动恢复'),
                      value: _safeMode,
                      onChanged: _exitProtectionMode == _ExitProtectionMode.localPassword
                          ? (enabled) {
                              setState(() => _safeMode = enabled);
                              _scheduleAutoSave(_saveDisplaySettings);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Divider(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'F2A 二次验证',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '启用后，退出放映时需要输入手机网页中的动态验证码。网页会自行保存名称和密钥。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _f2aFactors.isEmpty
                          ? '未绑定 F2A 密钥'
                          : '已绑定 ${_f2aFactors.length} 组 F2A 密钥',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _enrollF2aFactor,
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('新增 F2A'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _f2aFactors.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    _f2aFactors = const [];
                                    _f2aEnabled = false;
                                  });
                                  _scheduleAutoSave(_saveDisplaySettings);
                                },
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('清空 F2A'),
                        ),
                      ],
                    ),
                    if (_f2aFactors.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Column(
                        children: _f2aFactors.asMap().entries.map((entry) {
                          final index = entry.key;
                          final factor = entry.value;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.phonelink_lock_outlined),
                            title: Text('F2A ${index + 1}'),
                            subtitle: const Text('已绑定并可用于退出验证'),
                            trailing: IconButton(
                              tooltip: '删除',
                              onPressed: () => _removeF2aFactor(factor.id),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
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
              ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
