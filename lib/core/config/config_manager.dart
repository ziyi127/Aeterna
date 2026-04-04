import 'dart:async';
import 'dart:convert';

import 'package:aeterna/core/config/exam_aware_2_parser.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExamPlanConfig {
  const ExamPlanConfig({
    required this.examTitle,
    required this.startDate,
    required this.endDate,
    required this.exams,
  });

  final String examTitle;
  final DateTime startDate;
  final DateTime endDate;
  final List<ExamSlot> exams;

  Map<String, dynamic> toJson() {
    return {
      'examTitle': examTitle,
      'startDate': _dateOnly(startDate).toIso8601String(),
      'endDate': _dateOnly(endDate).toIso8601String(),
      'exams': exams
          .map(
            (e) => {
              'subject': e.subject,
              'start': e.start.toIso8601String(),
              'end': e.end.toIso8601String(),
              if (e.materials.isNotEmpty)
                'materials': e.materials.map((m) => m.toJson()).toList(),
              if (e.message.isNotEmpty) 'message': e.message,
            },
          )
          .toList(),
    };
  }

  static ExamPlanConfig fromJson(Map<String, dynamic> json) {
    final examsRaw = (json['exams'] as List?) ?? const [];
    final exams = examsRaw
        .map(
          (item) {
            final materialsRaw = (item['materials'] as List?) ?? const [];
            final materials = materialsRaw
                .map(
                  (m) => ExamMaterial.fromJson(m as Map<String, dynamic>),
                )
                .toList();
            return ExamSlot(
              subject: item['subject'] as String,
              start: DateTime.parse(item['start'] as String),
              end: DateTime.parse(item['end'] as String),
              materials: materials,
              message: (item['message'] as String?) ?? '',
            );
          },
        )
        .toList();

    final fallbackDate = DateTime.now();
    final parsedStart = DateTime.tryParse((json['startDate'] as String?) ?? '');
    final parsedEnd = DateTime.tryParse((json['endDate'] as String?) ?? '');
    final startDate = parsedStart ?? _inferStartDate(exams) ?? fallbackDate;
    final endDate = parsedEnd ?? _inferEndDate(exams) ?? startDate;

    return ExamPlanConfig(
      examTitle: (json['examTitle'] as String?)?.trim().isNotEmpty == true
          ? (json['examTitle'] as String).trim()
          : '未命名考试',
      startDate: _dateOnly(startDate),
      endDate: _dateOnly(endDate),
      exams: exams,
    );
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static DateTime? _inferStartDate(List<ExamSlot> exams) {
    if (exams.isEmpty) {
      return null;
    }
    var min = exams.first.start;
    for (final exam in exams) {
      if (exam.start.isBefore(min)) {
        min = exam.start;
      }
    }
    return _dateOnly(min);
  }

  static DateTime? _inferEndDate(List<ExamSlot> exams) {
    if (exams.isEmpty) {
      return null;
    }
    var max = exams.first.end;
    for (final exam in exams) {
      if (exam.end.isAfter(max)) {
        max = exam.end;
      }
    }
    return _dateOnly(max);
  }
}

class DisplaySettings {
  const DisplaySettings({
    required this.fontScale,
    required this.roomLabel,
    this.themeMode = 'system',
    this.themePalette = 'emerald',
    this.maxDriftStepMs = 250,
    this.exitPasswordEnabled = false,
    this.exitPassword = '',
    this.safeMode = false,
    this.twoFactorEnabled = false,
    this.twoFactorEntries = const <TwoFactorEntry>[],
  });

  final double fontScale;
  final String roomLabel;
  final String themeMode;
  final String themePalette;
  final int maxDriftStepMs;
  final bool exitPasswordEnabled;
  final String exitPassword;
  final bool safeMode;
  final bool twoFactorEnabled;
  final List<TwoFactorEntry> twoFactorEntries;

  DisplaySettings copyWith({
    double? fontScale,
    String? roomLabel,
    String? themeMode,
    String? themePalette,
    int? maxDriftStepMs,
    bool? exitPasswordEnabled,
    String? exitPassword,
    bool? safeMode,
    bool? f2aEnabled,
    List<TwoFactorEntry>? f2aFactors,
  }) {
    return DisplaySettings(
      fontScale: fontScale ?? this.fontScale,
      roomLabel: roomLabel ?? this.roomLabel,
      themeMode: themeMode ?? this.themeMode,
      themePalette: themePalette ?? this.themePalette,
      maxDriftStepMs: maxDriftStepMs ?? this.maxDriftStepMs,
      exitPasswordEnabled: exitPasswordEnabled ?? this.exitPasswordEnabled,
      exitPassword: exitPassword ?? this.exitPassword,
      safeMode: safeMode ?? this.safeMode,
      twoFactorEnabled: f2aEnabled ?? twoFactorEnabled,
      twoFactorEntries: f2aFactors ?? twoFactorEntries,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fontScale': fontScale,
      'roomLabel': roomLabel,
      'themeMode': themeMode,
      'themePalette': themePalette,
      'maxDriftStepMs': maxDriftStepMs,
      'exitPasswordEnabled': exitPasswordEnabled,
      'exitPassword': exitPassword,
      'safeMode': safeMode,
      'f2aEnabled': twoFactorEnabled,
      'f2aFactors': twoFactorEntries.map((e) => e.toJson()).toList(),
    };
  }

  static DisplaySettings fromJson(Map<String, dynamic> json) {
    final factorsRaw = (json['f2aFactors'] as List?) ?? const [];
    return DisplaySettings(
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      roomLabel: (json['roomLabel'] as String?)?.trim().isNotEmpty == true
          ? (json['roomLabel'] as String).trim()
          : '试室 A01',
      themeMode: (json['themeMode'] as String?)?.trim().isNotEmpty == true
          ? (json['themeMode'] as String).trim()
          : 'system',
      themePalette: (json['themePalette'] as String?)?.trim().isNotEmpty == true
          ? (json['themePalette'] as String).trim()
          : 'emerald',
      maxDriftStepMs: (json['maxDriftStepMs'] as num?)?.toInt() ?? 250,
      exitPasswordEnabled: (json['exitPasswordEnabled'] as bool?) ?? false,
      exitPassword: (json['exitPassword'] as String?) ?? '',
      safeMode: (json['safeMode'] as bool?) ?? false,
      twoFactorEnabled: (json['f2aEnabled'] as bool?) ?? false,
      twoFactorEntries: factorsRaw
          .whereType<Map>()
          .map((item) => TwoFactorEntry.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }
}

class TwoFactorEntry {
  const TwoFactorEntry({
    required this.id,
    required this.name,
    required this.secret,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final String secret;
  final int createdAtMs;

  TwoFactorEntry copyWith({
    String? id,
    String? name,
    String? secret,
    int? createdAtMs,
  }) {
    return TwoFactorEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      secret: secret ?? this.secret,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'secret': secret,
      'createdAtMs': createdAtMs,
    };
  }

  static TwoFactorEntry fromJson(Map<String, dynamic> json) {
    return TwoFactorEntry(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : DateTime.now().millisecondsSinceEpoch.toString(),
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String).trim()
          : '未命名设备',
      secret: (json['secret'] as String?)?.trim() ?? '',
      createdAtMs:
          (json['createdAtMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class SyncSettings {
  const SyncSettings({
    required this.ntpServers,
    required this.modeKey,
    required this.manualOffsetMs,
    required this.autoSyncEnabled,
    required this.autoSyncIntervalMinutes,
  });

  final List<String> ntpServers;
  final String modeKey;
  final int manualOffsetMs;
  final bool autoSyncEnabled;
  final int autoSyncIntervalMinutes;

  TimeSourceMode get mode => TimeSourceModeLabel.fromKey(modeKey);

  Map<String, dynamic> toJson() {
    return {
      'ntpServers': ntpServers,
      'modeKey': modeKey,
      'manualOffsetMs': manualOffsetMs,
      'autoSyncEnabled': autoSyncEnabled,
      'autoSyncIntervalMinutes': autoSyncIntervalMinutes,
    };
  }

  static SyncSettings fromJson(Map<String, dynamic> json) {
    final serversRaw = (json['ntpServers'] as List?)?.whereType<String>().toList() ??
        <String>[];
    final legacyAddress = (json['ntpAddress'] as String?)?.trim() ?? '';
    final servers = serversRaw
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final mergedServers = servers.isNotEmpty
        ? servers
        : (legacyAddress.isEmpty ? const <String>[] : <String>[legacyAddress]);

    return SyncSettings(
      ntpServers: mergedServers,
      modeKey: (json['modeKey'] as String?)?.trim().isNotEmpty == true
          ? (json['modeKey'] as String).trim()
          : TimeSourceMode.offlineManual.key,
      manualOffsetMs: (json['manualOffsetMs'] as num?)?.toInt() ?? 0,
      autoSyncEnabled: (json['autoSyncEnabled'] as bool?) ?? true,
      autoSyncIntervalMinutes:
          ((json['autoSyncIntervalMinutes'] as num?)?.toInt() ?? 5).clamp(1, 180),
    );
  }
}

class ConfigManager {
  static const String _examsKey = 'aeterna_exams';
  static const String _displaySettingsKey = 'aeterna_display_settings';
  static const String _planKey = 'aeterna_exam_plan';
  static const String _syncSettingsKey = 'aeterna_sync_settings';
  static const String _welcomeShownKey = 'aeterna_welcome_shown';

  static bool looksLikePasswordHash(String value) {
    return RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value);
  }

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  static String normalizePasswordStorage(String passwordValue) {
    final trimmed = passwordValue.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (looksLikePasswordHash(trimmed)) {
      return trimmed.toLowerCase();
    }
    return hashPassword(trimmed);
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static String _encodeExams(List<ExamSlot> exams) {
    final json = exams
        .map(
          (e) => {
            'subject': e.subject,
            'start': e.start.toIso8601String(),
            'end': e.end.toIso8601String(),
            if (e.materials.isNotEmpty)
              'materials': e.materials.map((m) => m.toJson()).toList(),
            if (e.message.isNotEmpty) 'message': e.message,
          },
        )
        .toList();
    return jsonEncode(json);
  }

  static List<ExamSlot> _decodeExams(dynamic raw) {
    final list = raw as List;
    return list
        .map(
          (item) {
            final materialsRaw = (item['materials'] as List?) ?? const [];
            final materials = materialsRaw
                .map(
                  (m) => ExamMaterial.fromJson(m as Map<String, dynamic>),
                )
                .toList();
            return ExamSlot(
              subject: item['subject'] as String,
              start: DateTime.parse(item['start'] as String),
              end: DateTime.parse(item['end'] as String),
              materials: materials,
              message: (item['message'] as String?) ?? '',
            );
          },
        )
        .toList();
  }

  static Future<void> saveExams(List<ExamSlot> exams) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_examsKey, _encodeExams(exams));
  }

  static Future<List<ExamSlot>> loadExams() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_examsKey);
    if (jsonStr == null) {
      return [];
    }
    try {
      return _decodeExams(jsonDecode(jsonStr));
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePlanConfig(ExamPlanConfig plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_planKey, jsonEncode(plan.toJson()));
  }

  static Future<ExamPlanConfig?> loadPlanConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final planJson = prefs.getString(_planKey);
    if (planJson != null) {
      try {
        final map = jsonDecode(planJson) as Map<String, dynamic>;
        return ExamPlanConfig.fromJson(map);
      } catch (_) {
        // Ignore invalid plan JSON and try fallback below.
      }
    }

    // Backward compatibility with old exam-only storage.
    final legacyExams = await loadExams();
    if (legacyExams.isEmpty) {
      return null;
    }
    final first = legacyExams.first.start;
    final last = legacyExams.last.end;
    return ExamPlanConfig(
      examTitle: '未命名考试',
      startDate: _dateOnly(first),
      endDate: _dateOnly(last),
      exams: legacyExams,
    );
  }

  static String exportToJson(
    List<ExamSlot> exams, {
    String examTitle = '未命名考试',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (exams.isEmpty) {
      final now = DateTime.now();
      final plan = ExamPlanConfig(
        examTitle: examTitle,
        startDate: _dateOnly(startDate ?? now),
        endDate: _dateOnly(endDate ?? now),
        exams: const [],
      );
      return jsonEncode(plan.toJson());
    }

    final inferredStart = exams.first.start;
    final inferredEnd = exams.last.end;
    final plan = ExamPlanConfig(
      examTitle: examTitle,
      startDate: _dateOnly(startDate ?? inferredStart),
      endDate: _dateOnly(endDate ?? inferredEnd),
      exams: exams,
    );
    return jsonEncode(plan.toJson());
  }

  static ExamPlanConfig? importPlanFromJson(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      
      // 尝试检测 ExamAware2 格式
      if (decoded is Map<String, dynamic> && 
          ExamAware2Parser.isExamAware2Format(decoded)) {
        return _importFromExamAware2(decoded);
      }
      
      // 原生 Aeterna 格式处理
      if (decoded is List) {
        final exams = _decodeExams(decoded);
        if (exams.isEmpty) {
          return null;
        }
        return ExamPlanConfig(
          examTitle: '未命名考试',
          startDate: _dateOnly(exams.first.start),
          endDate: _dateOnly(exams.last.end),
          exams: exams,
        );
      }
      if (decoded is Map<String, dynamic>) {
        return ExamPlanConfig.fromJson(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 从 ExamAware2 格式导入计划
  static ExamPlanConfig? _importFromExamAware2(Map<String, dynamic> json) {
    try {
      final config = ExamAware2Config.fromJson(json);
      if (!config.isValid()) {
        return null;
      }
      
      // 转换 ExamAware2 信息为 ExamSlot
      final exams = <ExamSlot>[];
      for (final info in config.examInfos) {
        try {
          final slot = info.toExamSlot(message: config.message);
          exams.add(slot);
        } catch (_) {
          // 跳过无效的考试信息
        }
      }
      
      if (exams.isEmpty) {
        return null;
      }
      
      // 推断日期范围
      exams.sort((a, b) => a.start.compareTo(b.start));
      final startDate = _dateOnly(exams.first.start);
      final endDate = _dateOnly(exams.last.end);
      
      return ExamPlanConfig(
        examTitle: config.examName,
        startDate: startDate,
        endDate: endDate,
        exams: exams,
      );
    } catch (_) {
      return null;
    }
  }

  static List<ExamSlot> importFromJson(String jsonStr) {
    return importPlanFromJson(jsonStr)?.exams ?? [];
  }

  static Future<void> saveDisplaySettings(DisplaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final storageSettings = settings.copyWith(
      exitPassword: normalizePasswordStorage(settings.exitPassword),
    );
    await prefs.setString(_displaySettingsKey, jsonEncode(storageSettings.toJson()));
  }

  static Future<DisplaySettings> loadDisplaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_displaySettingsKey);
    if (jsonStr == null) {
      return const DisplaySettings(fontScale: 1.0, roomLabel: '试室 A01');
    }
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final settings = DisplaySettings.fromJson(data);
      final normalizedPassword = normalizePasswordStorage(settings.exitPassword);
      if (normalizedPassword != settings.exitPassword) {
        unawaited(
          saveDisplaySettings(
            settings.copyWith(exitPassword: normalizedPassword),
          ),
        );
        return settings.copyWith(exitPassword: normalizedPassword);
      }
      return settings.copyWith(exitPassword: normalizedPassword);
    } catch (_) {
      return const DisplaySettings(fontScale: 1.0, roomLabel: '试室 A01');
    }
  }

  static Future<void> saveSyncSettings(SyncSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncSettingsKey, jsonEncode(settings.toJson()));
  }

  static Future<SyncSettings> loadSyncSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_syncSettingsKey);
    if (jsonStr == null) {
      return const SyncSettings(
        ntpServers: <String>[],
        modeKey: 'offline-manual',
        manualOffsetMs: 0,
        autoSyncEnabled: true,
        autoSyncIntervalMinutes: 5,
      );
    }
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return SyncSettings.fromJson(data);
    } catch (_) {
      return const SyncSettings(
        ntpServers: <String>[],
        modeKey: 'offline-manual',
        manualOffsetMs: 0,
        autoSyncEnabled: true,
        autoSyncIntervalMinutes: 5,
      );
    }
  }

  static Future<bool> isWelcomeShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_welcomeShownKey) ?? false;
  }

  static Future<void> setWelcomeShown(bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_welcomeShownKey, shown);
  }
}
