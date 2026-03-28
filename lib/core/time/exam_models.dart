import 'package:flutter/material.dart';

enum ExamState { done, active, upcoming }

class ExamSlot {
  const ExamSlot({
    required this.subject,
    required this.start,
    required this.end,
  });

  final String subject;
  final DateTime start;
  final DateTime end;

  ExamSlot copyWith({String? subject, DateTime? start, DateTime? end}) {
    return ExamSlot(
      subject: subject ?? this.subject,
      start: start ?? this.start,
      end: end ?? this.end,
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
