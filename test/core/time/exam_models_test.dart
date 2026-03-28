import 'package:aeterna/core/time/exam_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExamSlot', () {
    final start = DateTime(2026, 3, 28, 9);
    final end = DateTime(2026, 3, 28, 10, 20);
    final slot = ExamSlot(subject: '数学', start: start, end: end);

    test('stateAt returns upcoming before start', () {
      final now = DateTime(2026, 3, 28, 8, 59);
      expect(slot.stateAt(now), ExamState.upcoming);
    });

    test('stateAt returns active in window', () {
      final now = DateTime(2026, 3, 28, 9, 30);
      expect(slot.stateAt(now), ExamState.active);
    });

    test('progressAt clamps range', () {
      expect(slot.progressAt(start.subtract(const Duration(minutes: 1))), 0);
      expect(slot.progressAt(end.add(const Duration(minutes: 1))), 1);
    });

    test('remainingAt returns remaining duration for active slot', () {
      final now = DateTime(2026, 3, 28, 9, 50);
      expect(slot.remainingAt(now), const Duration(minutes: 30));
    });
  });
}
