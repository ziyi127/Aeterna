import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNtpService extends NtpService {
  _FakeNtpService({this.result, this.error});

  final NtpSyncResult? result;
  final Object? error;

  @override
  Future<NtpSyncResult> fetchNetworkTime({
    required TimeSourceMode mode,
    required List<String> addresses,
  }) async {
    if (error != null) {
      throw error!;
    }
    return result ??
        NtpSyncResult(
          networkTime: DateTime(2026, 4, 4, 10, 0, 0),
          server: 'fake',
        );
  }
}

void main() {
  group('TimerController', () {
    test('planRevision increments on plan mutations', () {
      final controller = TimerController(
        exams: <ExamSlot>[],
        ntpService: _FakeNtpService(),
      );

      expect(controller.planRevision, 0);

      controller.addExam(
        ExamSlot(
          subject: '数学',
          start: DateTime(2026, 4, 4, 9, 0, 0),
          end: DateTime(2026, 4, 4, 11, 0, 0),
        ),
      );
      expect(controller.planRevision, 1);

      controller.updateExam(
        0,
        ExamSlot(
          subject: '语文',
          start: DateTime(2026, 4, 4, 9, 0, 0),
          end: DateTime(2026, 4, 4, 11, 0, 0),
        ),
      );
      expect(controller.planRevision, 2);

      controller.removeExam(0);
      expect(controller.planRevision, 3);

      controller.dispose();
    });

    test('setExamMeta swaps inverted date range', () {
      final controller = TimerController(
        exams: <ExamSlot>[],
        ntpService: _FakeNtpService(),
      );
      final later = DateTime(2026, 4, 8);
      final earlier = DateTime(2026, 4, 2);

      controller.setExamMeta(
        examTitle: '期中考试',
        startDate: later,
        endDate: earlier,
      );

      expect(controller.planStartDate, earlier);
      expect(controller.planEndDate, later);
      expect(controller.examTitle, '期中考试');
      controller.dispose();
    });

    test('countdown and labels are derived from active exam', () {
      final controller = TimerController(
        exams: <ExamSlot>[
          ExamSlot(
            subject: '英语',
            start: DateTime(2026, 4, 4, 9, 0, 0),
            end: DateTime(2026, 4, 4, 10, 0, 0),
          ),
        ],
        ntpService: _FakeNtpService(),
        nowProvider: () => DateTime(2026, 4, 4, 9, 30, 0),
      );

      expect(controller.subjectLabel, '英语');
      expect(controller.periodLabel, '09:00 - 10:00');
      expect(controller.formatCountdown(), '00:30:00');
      expect(controller.isNearEnd, isFalse);
      controller.dispose();
    });

    test('isNearEnd is true in last 15 minutes of active exam', () {
      final controller = TimerController(
        exams: <ExamSlot>[
          ExamSlot(
            subject: '英语',
            start: DateTime(2026, 4, 4, 9, 0, 0),
            end: DateTime(2026, 4, 4, 10, 0, 0),
          ),
        ],
        ntpService: _FakeNtpService(),
        nowProvider: () => DateTime(2026, 4, 4, 9, 50, 0),
      );

      expect(controller.isNearEnd, isTrue);
      controller.dispose();
    });

    test('syncNow success updates sync status and offsets', () async {
      final localNow = DateTime(2026, 4, 4, 10, 0, 0);
      final controller = TimerController(
        exams: <ExamSlot>[],
        ntpService: _FakeNtpService(
          result: NtpSyncResult(
            networkTime: localNow.add(const Duration(milliseconds: 250)),
            server: 'ntp.test',
          ),
        ),
        nowProvider: () => localNow,
      );

      controller.setMode(TimeSourceMode.cloudPull);
      await controller.syncNow();

      expect(controller.syncState, SyncState.success);
      expect(controller.lastSyncServer, 'ntp.test');
      expect(controller.networkOffsetMs, 250);
      expect(controller.currentOffsetMs, 250);
      controller.dispose();
    });

    test('syncNow failure sets fallback status', () async {
      final controller = TimerController(
        exams: <ExamSlot>[],
        ntpService: _FakeNtpService(error: StateError('network down')),
      );

      controller.setMode(TimeSourceMode.intranetSync);
      await controller.syncNow();

      expect(controller.syncState, SyncState.failure);
      expect(controller.syncStatus, '同步失败，已回退本地');
      expect(controller.syncErrorMessage, contains('network down'));
      controller.dispose();
    });
  });
}
