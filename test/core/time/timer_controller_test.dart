import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNtpService extends NtpService {
  FakeNtpService({required this.fetch, this.shouldThrow = false});

  final DateTime Function() fetch;
  final bool shouldThrow;

  @override
  Future<DateTime> fetchNetworkTime({
    required TimeSourceMode mode,
    required String address,
  }) async {
    if (shouldThrow) {
      throw StateError('ntp unreachable');
    }
    return fetch();
  }
}

class CountingNtpService extends NtpService {
  CountingNtpService({required this.now});

  final DateTime Function() now;
  int calls = 0;

  @override
  Future<DateTime> fetchNetworkTime({
    required TimeSourceMode mode,
    required String address,
  }) async {
    calls += 1;
    return now();
  }
}

void main() {
  final base = DateTime(2026, 3, 28, 9);
  final exams = [
    ExamSlot(
      subject: '语文',
      start: base,
      end: base.add(const Duration(hours: 1)),
    ),
  ];

  test('setMode and setNtpAddress update state', () {
    final controller = TimerController(
      exams: exams,
      ntpService: FakeNtpService(fetch: () => base),
      nowProvider: () => base,
    );

    controller.setNtpAddress('pool.ntp.org');
    controller.setMode(TimeSourceMode.cloudPull);

    expect(controller.ntpAddress, 'pool.ntp.org');
    expect(controller.mode, TimeSourceMode.cloudPull);
  });

  test('sync offset is applied with drift limit', () async {
    var now = base;
    final controller = TimerController(
      exams: exams,
      ntpService: FakeNtpService(
        fetch: () => now.add(const Duration(seconds: 5)),
      ),
      nowProvider: () => now,
    );

    controller.setMode(TimeSourceMode.cloudPull);
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final diff = controller.now.difference(now).inMilliseconds;
    expect(diff, inInclusiveRange(200, 260));

    controller.dispose();
  });

  test('sync failure falls back to local status', () async {
    final controller = TimerController(
      exams: exams,
      ntpService: FakeNtpService(fetch: () => base, shouldThrow: true),
      nowProvider: () => base,
    );

    controller.setMode(TimeSourceMode.cloudPull);
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.syncStatus, '同步失败，已回退本地');

    controller.dispose();
  });

  test('offline mode does not attempt auto sync during ticks', () async {
    var now = base;
    final ntp = CountingNtpService(now: () => now);
    final controller = TimerController(
      exams: [
        ExamSlot(
          subject: '语文',
          start: base,
          end: base.add(const Duration(hours: 1)),
        ),
      ],
      ntpService: ntp,
      nowProvider: () => now,
    );

    controller.setMode(TimeSourceMode.offlineManual);
    controller.start();

    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(ntp.calls, 0);
    expect(controller.syncState, SyncState.idle);
    controller.dispose();
  });

  test('syncNow updates sync state on success', () async {
    var now = base;
    final controller = TimerController(
      exams: [
        ExamSlot(
          subject: '语文',
          start: base,
          end: base.add(const Duration(hours: 1)),
        ),
      ],
      ntpService: FakeNtpService(
        fetch: () => now.add(const Duration(seconds: 2)),
      ),
      nowProvider: () => now,
    );

    controller.setMode(TimeSourceMode.cloudPull);
    await controller.syncNow();

    expect(controller.syncState, SyncState.success);
    expect(controller.syncErrorMessage, isEmpty);
    expect(controller.lastSyncAt, isNotNull);
    controller.dispose();
  });

  test('custom drift step applies larger correction per sync', () async {
    var now = base;
    final controller = TimerController(
      exams: [
        ExamSlot(
          subject: '语文',
          start: base,
          end: base.add(const Duration(hours: 1)),
        ),
      ],
      ntpService: FakeNtpService(
        fetch: () => now.add(const Duration(seconds: 5)),
      ),
      nowProvider: () => now,
    );

    controller.setMode(TimeSourceMode.cloudPull);
    controller.setMaxDriftStepMs(800);
    await controller.syncNow();

    expect(controller.lastAppliedDriftMs, 800);
    expect(controller.currentOffsetMs, 800);
    controller.dispose();
  });

  test('exam list supports add update remove in editor flow', () {
    final controller = TimerController(
      exams: [
        ExamSlot(
          subject: '英语',
          start: base.add(const Duration(hours: 3)),
          end: base.add(const Duration(hours: 4)),
        ),
      ],
      ntpService: FakeNtpService(fetch: () => base),
      nowProvider: () => base,
    );

    controller.addExam(
      ExamSlot(
        subject: '数学',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
      ),
    );
    expect(controller.exams.first.subject, '数学');

    controller.updateExam(
      0,
      controller.exams.first.copyWith(subject: '数学(调整)'),
    );
    expect(controller.exams.first.subject, '数学(调整)');

    controller.removeExam(1);
    expect(controller.exams.length, 1);
  });
}
