import 'dart:convert';

import 'package:aeterna/core/time/exam_models.dart';

/// ExamAware2 友商格式的数据模型和转换器
/// 支持导入 ExamAware2 JSON 文件并转换为 Aeterna 格式

/// ExamAware2 物料信息
class ExamAware2Material {
  const ExamAware2Material({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final int quantity;
  final String unit;

  factory ExamAware2Material.fromJson(Map<String, dynamic> json) {
    return ExamAware2Material(
      name: (json['name'] as String?)?.trim() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unit: (json['unit'] as String?)?.trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
    };
  }

  @override
  String toString() => '$name x$quantity $unit';
}

/// ExamAware2 单个考试信息
class ExamAware2Info {
  const ExamAware2Info({
    required this.name,
    required this.start,
    required this.end,
    required this.alertTime,
    this.materials = const [],
  });

  final String name; // 科目名称
  final String start; // 开始时间，格式: "YYYY-MM-DD HH:mm:ss" 或 ISO 8601
  final String end; // 结束时间，格式: "YYYY-MM-DD HH:mm:ss" 或 ISO 8601
  final int alertTime; // 提前提醒分钟数
  final List<ExamAware2Material> materials; // 物料清单

  factory ExamAware2Info.fromJson(Map<String, dynamic> json) {
    final materialsRaw = (json['materials'] as List?) ?? const [];
    final materials = materialsRaw
        .map(
          (item) =>
              ExamAware2Material.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    return ExamAware2Info(
      name: (json['name'] as String?)?.trim() ?? '',
      start: (json['start'] as String?)?.trim() ?? '',
      end: (json['end'] as String?)?.trim() ?? '',
      alertTime: (json['alertTime'] as num?)?.toInt() ?? 5,
      materials: materials,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'start': start,
      'end': end,
      'alertTime': alertTime,
      if (materials.isNotEmpty) 'materials': materials.map((m) => m.toJson()).toList(),
    };
  }

  /// 转换为 Aeterna ExamSlot 格式
  ExamSlot toExamSlot({String message = ''}) {
    final startTime = _parseDateTime(start);
    final endTime = _parseDateTime(end);
    if (startTime == null || endTime == null) {
      throw FormatException('Invalid date format: "$start" or "$end"');
    }
    return ExamSlot(
      subject: name,
      start: startTime,
      end: endTime,
      materials: materials
          .map((m) => ExamMaterial(
                name: m.name,
                quantity: m.quantity,
                unit: m.unit,
              ))
          .toList(),
      message: message,
    );
  }

  /// 解析時間字符串
  /// 支持格式:
  /// - "2024-12-25 09:00:00"
  /// - "2024-12-25T09:00:00"
  /// - "2024-12-25T09:00:00Z"
  static DateTime? _parseDateTime(String timeStr) {
    if (timeStr.isEmpty) {
      return null;
    }
    try {
      // 尝试标准 ISO 8601 格式
      try {
        return DateTime.parse(timeStr);
      } catch (_) {
        // 如果失败，尝试 "YYYY-MM-DD HH:mm:ss" 格式
        final parts = timeStr.split(' ');
        if (parts.length == 2) {
          final iso = '${parts[0]}T${parts[1]}';
          return DateTime.parse(iso);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

/// ExamAware2 配置文件格式（顶级）
class ExamAware2Config {
  const ExamAware2Config({
    required this.examName,
    required this.message,
    required this.examInfos,
  });

  final String examName; // 考试名称
  final String message; // 关联消息（如年级班级）
  final List<ExamAware2Info> examInfos; // 考试信息数组

  factory ExamAware2Config.fromJson(Map<String, dynamic> json) {
    final infosRaw = (json['examInfos'] as List?) ?? const [];
    final infos = infosRaw
        .map(
          (item) => ExamAware2Info.fromJson(item as Map<String, dynamic>),
        )
        .toList();

    return ExamAware2Config(
      examName: (json['examName'] as String?)?.trim() ?? '未命名考试',
      message: (json['message'] as String?)?.trim() ?? '',
      examInfos: infos,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'examName': examName,
      'message': message,
      'examInfos': examInfos.map((e) => e.toJson()).toList(),
    };
  }

  /// 验证配置的有效性
  bool isValid() {
    if (examName.isEmpty || examInfos.isEmpty) {
      return false;
    }
    // 验证所有考试信息的必需字段和时间有效性
    for (final info in examInfos) {
      if (info.name.isEmpty || info.start.isEmpty || info.end.isEmpty) {
        return false;
      }
      // 尝试解析时间以验证格式
      try {
        info.toExamSlot();
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// 检查是否有时间重叠
  bool hasTimeOverlap() {
    if (examInfos.isEmpty) {
      return false;
    }
    final slots = <ExamSlot>[];
    for (final info in examInfos) {
      try {
        slots.add(info.toExamSlot());
      } catch (_) {
        // 忽略无效的时间信息
      }
    }
    if (slots.length < 2) {
      return false;
    }
    // 按开始时间排序
    slots.sort((a, b) => a.start.compareTo(b.start));
    // 检查是否有重叠
    for (int i = 0; i < slots.length - 1; i++) {
      if (slots[i].end.isAfter(slots[i + 1].start)) {
        return true;
      }
    }
    return false;
  }
}

/// ExamAware2 格式检测和解析器
class ExamAware2Parser {
  /// 检测 JSON 字符串是否为 ExamAware2 格式
  static bool isExamAware2Format(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return false;
    }
    // ExamAware2 必须有 examName, message 和 examInfos 字段
    return json.containsKey('examName') &&
        json.containsKey('examInfos') &&
        json['examInfos'] is List;
  }

  /// 尝试解析 ExamAware2 JSON 字符串
  static ExamAware2Config? tryParse(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr);
      if (!isExamAware2Format(json)) {
        return null;
      }
      return ExamAware2Config.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 检测并尝试解析 JSON 字符串
  /// 返回 null 表示不是有效的 ExamAware2 格式
  static ParseResult? detect(String jsonStr) {
    try {
      final json = jsonDecode(jsonStr);
      if (!isExamAware2Format(json)) {
        return null;
      }
      final config = ExamAware2Config.fromJson(json as Map<String, dynamic>);
      if (!config.isValid()) {
        return ParseResult.invalid('配置数据不完整或格式错误');
      }
      return ParseResult.success(config);
    } catch (e) {
      return ParseResult.invalid('JSON 解析错误: $e');
    }
  }
}

/// 解析结果
class ParseResult {
  const ParseResult._(
    this.isSuccess,
    this.config,
    this.errorMessage,
  );

  final bool isSuccess;
  final ExamAware2Config? config;
  final String? errorMessage;

  factory ParseResult.success(ExamAware2Config config) {
    return ParseResult._(true, config, null);
  }

  factory ParseResult.invalid(String error) {
    return ParseResult._(false, null, error);
  }
}

/// ExamAware2 到 Aeterna 的转换工具
class ExamAware2Converter {
  /// 将 ExamAware2 配置转换为 Aeterna ExamPlanConfig
  static Map<String, dynamic> toAeternaFormat(ExamAware2Config config) {
    // 转换所有考试信息
    final exams = <Map<String, dynamic>>[];
    for (final info in config.examInfos) {
      try {
        final slot = info.toExamSlot();
        exams.add({
          'subject': slot.subject,
          'start': slot.start.toIso8601String(),
          'end': slot.end.toIso8601String(),
        });
      } catch (_) {
        // 跳过无效的考试信息
      }
    }

    // 推断日期范围
    DateTime? startDate;
    DateTime? endDate;
    if (exams.isNotEmpty) {
      final starts = config.examInfos
          .map((e) => ExamAware2Info._parseDateTime(e.start))
          .whereType<DateTime>()
          .toList();
      final ends = config.examInfos
          .map((e) => ExamAware2Info._parseDateTime(e.end))
          .whereType<DateTime>()
          .toList();

      if (starts.isNotEmpty) {
        starts.sort();
        startDate = _dateOnly(starts.first);
      }
      if (ends.isNotEmpty) {
        ends.sort();
        endDate = _dateOnly(ends.last);
      }
    }

    final now = DateTime.now();
    startDate ??= _dateOnly(now);
    endDate ??= startDate;

    // 确保 endDate >= startDate
    if (endDate.isBefore(startDate)) {
      endDate = startDate;
    }

    return {
      'examTitle': config.examName,
      'startDate': startDate.toIso8601String().split('T')[0],
      'endDate': endDate.toIso8601String().split('T')[0],
      'exams': exams,
      'source': 'exam_aware_2', // 标记来源
      'sourceMessage': config.message, // 保存原始消息信息
    };
  }

  static DateTime _dateOnly(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);
}
