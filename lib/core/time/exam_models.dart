import 'package:flutter/material.dart';

enum ExamState { done, active, upcoming }

/// 考试所需材料
class ExamMaterial {
  const ExamMaterial({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name; // 材料名称，如"试卷"、"答题卡"
  final int quantity; // 数量
  final String unit; // 单位，如"份"、"张"

  ExamMaterial copyWith({
    String? name,
    int? quantity,
    String? unit,
  }) {
    return ExamMaterial(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
    );
  }

  /// 返回格式化的显示文本，如"试卷(1份)"
  String toDisplayString() => '$name($quantity$unit)';

  /// JSON 序列化
  Map<String, dynamic> toJson() => {
        'name': name,
        'quantity': quantity,
        'unit': unit,
      };

  /// 从 JSON 反序列化
  factory ExamMaterial.fromJson(Map<String, dynamic> json) => ExamMaterial(
        name: (json['name'] as String?)?.trim() ?? '',
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unit: (json['unit'] as String?)?.trim() ?? '',
      );

  @override
  String toString() => toDisplayString();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExamMaterial &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          quantity == other.quantity &&
          unit == other.unit;

  @override
  int get hashCode => Object.hash(name, quantity, unit);
}

class ExamSlot {
  const ExamSlot({
    required this.subject,
    required this.start,
    required this.end,
    this.materials = const [],
    this.message = '',
  });

  final String subject;
  final DateTime start;
  final DateTime end;
  final List<ExamMaterial> materials;
  final String message; // 考试信息或备注，对标EA的message字段

  ExamSlot copyWith({
    String? subject,
    DateTime? start,
    DateTime? end,
    List<ExamMaterial>? materials,
    String? message,
  }) {
    return ExamSlot(
      subject: subject ?? this.subject,
      start: start ?? this.start,
      end: end ?? this.end,
      materials: materials ?? this.materials,
      message: message ?? this.message,
    );
  }

  ExamState stateAt(DateTime now) {
    if (now.isAfter(end)) {
      return ExamState.done;
    }
    if (now.isBefore(start)) {
      return ExamState.upcoming;
    }
    return ExamState.active;
  }

  double progressAt(DateTime now) {
    if (now.isBefore(start)) {
      return 0;
    }
    if (now.isAfter(end)) {
      return 1;
    }
    final totalMs = end.difference(start).inMilliseconds;
    final elapsedMs = now.difference(start).inMilliseconds;
    if (totalMs <= 0) {
      return 0;
    }
    return (elapsedMs / totalMs).clamp(0, 1);
  }

  Duration remainingAt(DateTime now) {
    if (now.isBefore(start)) {
      return start.difference(now);
    }
    if (now.isAfter(end)) {
      return Duration.zero;
    }
    return end.difference(now);
  }

  String windowText() {
    final startText = _formatHm(start);
    final endText = _formatHm(end);
    return '$startText - $endText';
  }

  static String _formatHm(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

extension ExamStateVisual on ExamState {
  String get label {
    switch (this) {
      case ExamState.done:
        return '已结束';
      case ExamState.active:
        return '进行中';
      case ExamState.upcoming:
        return '待开始';
    }
  }

  Color color(ColorScheme scheme) {
    switch (this) {
      case ExamState.done:
        return scheme.outline;
      case ExamState.active:
        return scheme.primary;
      case ExamState.upcoming:
        return scheme.secondary;
    }
  }
}
