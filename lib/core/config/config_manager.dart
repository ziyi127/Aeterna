import 'dart:convert';

import 'package:aeterna/core/time/exam_models.dart';
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
            },
          )
          .toList(),
    };
  }

  static ExamPlanConfig fromJson(Map<String, dynamic> json) {
    final examsRaw = (json['exams'] as List?) ?? const [];
    final exams = examsRaw
        .map(
          (item) => ExamSlot(
            subject: item['subject'] as String,
            start: DateTime.parse(item['start'] as String),
            end: DateTime.parse(item['end'] as String),
          ),
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
  });

  final double fontScale;
  final String roomLabel;
  final String themeMode;
  final String themePalette;

  DisplaySettings copyWith({
    double? fontScale,
    String? roomLabel,
    String? themeMode,
    String? themePalette,
  }) {
    return DisplaySettings(
      fontScale: fontScale ?? this.fontScale,
      roomLabel: roomLabel ?? this.roomLabel,
      themeMode: themeMode ?? this.themeMode,
      themePalette: themePalette ?? this.themePalette,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fontScale': fontScale,
      'roomLabel': roomLabel,
      'themeMode': themeMode,
      'themePalette': themePalette,
    };
  }

  static DisplaySettings fromJson(Map<String, dynamic> json) {
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
    );
  }
}

class ConfigManager {
  static const String _examsKey = 'aeterna_exams';
  static const String _displaySettingsKey = 'aeterna_display_settings';
  static const String _planKey = 'aeterna_exam_plan';

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static String _encodeExams(List<ExamSlot> exams) {
    final json = exams
        .map(
          (e) => {
            'subject': e.subject,
            'start': e.start.toIso8601String(),
            'end': e.end.toIso8601String(),
          },
        )
        .toList();
    return jsonEncode(json);
  }

  static List<ExamSlot> _decodeExams(dynamic raw) {
    final list = raw as List;
    return list
        .map(
          (item) => ExamSlot(
            subject: item['subject'] as String,
            start: DateTime.parse(item['start'] as String),
            end: DateTime.parse(item['end'] as String),
          ),
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

  static List<ExamSlot> importFromJson(String jsonStr) {
    return importPlanFromJson(jsonStr)?.exams ?? [];
  }

  static Future<void> saveDisplaySettings(DisplaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displaySettingsKey, jsonEncode(settings.toJson()));
  }

  static Future<DisplaySettings> loadDisplaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_displaySettingsKey);
    if (jsonStr == null) {
      return const DisplaySettings(fontScale: 1.0, roomLabel: '试室 A01');
    }
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return DisplaySettings.fromJson(data);
    } catch (_) {
      return const DisplaySettings(fontScale: 1.0, roomLabel: '试室 A01');
    }
  }
}
