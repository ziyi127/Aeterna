import 'dart:async';
import 'dart:math' as math;

import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/ntp_service.dart';
import 'package:aeterna/core/time/time_source_mode.dart';
import 'package:flutter/widgets.dart';

enum SyncState { idle, syncing, success, failure }

class TimerController extends ChangeNotifier {
  TimerController({
    required List<ExamSlot> exams,
    required NtpService ntpService,
    DateTime Function()? nowProvider,
  }) : _exams = exams,
       _ntpService = ntpService,
       _nowProvider = nowProvider ?? DateTime.now,
       _baseNow = (nowProvider ?? DateTime.now)();

  final NtpService _ntpService;
  final List<ExamSlot> _exams;
  final DateTime Function() _nowProvider;

  DateTime _baseNow;
  Duration _offset = Duration.zero;
  String _examTitle = '未命名考试';
  DateTime? _planStartDate;
  DateTime? _planEndDate;
  String _ntpAddress = '';
  TimeSourceMode _mode = TimeSourceMode.offlineManual;
  DateTime? _lastSyncAt;
  String _syncStatus = '离线手动';
  SyncState _syncState = SyncState.idle;
  String _syncErrorMessage = '';
  DateTime? _lastAutoSyncAttempt;
  int _maxDriftStepMs = 250;
  int _lastAppliedDriftMs = 0;
  int _planRevision = 0;

  Timer? _ticker;
  bool _syncing = false;
  bool _isDisposed = false;
  static const Duration _autoSyncInterval = Duration(seconds: 30);

  List<ExamSlot> get exams => List.unmodifiable(_exams);
  String get ntpAddress => _ntpAddress;
  String get examTitle => _examTitle;
  DateTime? get planStartDate => _planStartDate;
  DateTime? get planEndDate => _planEndDate;
  TimeSourceMode get mode => _mode;
  String get modeLabel => _mode.label;
  DateTime get now => _baseNow.add(_offset);
  DateTime? get lastSyncAt => _lastSyncAt;
  String get syncStatus => _syncStatus;
  SyncState get syncState => _syncState;
  String get syncErrorMessage => _syncErrorMessage;
  bool get isSyncing => _syncing;
  bool get isRunning => _ticker != null && !_isDisposed;
  int get maxDriftStepMs => _maxDriftStepMs;
  int get lastAppliedDriftMs => _lastAppliedDriftMs;
  int get currentOffsetMs => _offset.inMilliseconds;
  int get planRevision => _planRevision;

  void _markPlanChanged() {
    _planRevision++;
  }

  void addExam(ExamSlot slot) {
    _exams.add(slot);
    _sortExams();
    _markPlanChanged();
    notifyListeners();
  }

  void updateExam(int index, ExamSlot slot) {
    if (index < 0 || index >= _exams.length) {
      return;
    }
    _exams[index] = slot;
    _sortExams();
    _markPlanChanged();
    notifyListeners();
  }

  void removeExam(int index) {
    if (index < 0 || index >= _exams.length) {
      return;
    }
    _exams.removeAt(index);
    _markPlanChanged();
    notifyListeners();
  }

  void replaceAllExams(List<ExamSlot> newExams) {
    _exams.clear();
    _exams.addAll(newExams);
    _sortExams();
    _markPlanChanged();
    notifyListeners();
  }

  void setExamMeta({
    required String examTitle,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final title = examTitle.trim().isEmpty ? '未命名考试' : examTitle.trim();
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (end.isBefore(start)) {
      _examTitle = title;
      _planStartDate = end;
      _planEndDate = start;
      _markPlanChanged();
      notifyListeners();
      return;
    }
    _examTitle = title;
    _planStartDate = start;
    _planEndDate = end;
    _markPlanChanged();
    notifyListeners();
  }

  ExamSlot? get activeExam {
    for (final exam in _exams) {
      if (exam.stateAt(now) == ExamState.active) {
        return exam;
      }
    }
    return null;
  }

  ExamSlot? get nextExam {
    for (final exam in _exams) {
      if (exam.stateAt(now) == ExamState.upcoming) {
        return exam;
      }
    }
    return null;
  }

  String get subjectLabel =>
      activeExam?.subject ?? nextExam?.subject ?? '今日考试已结束';

  Duration get countdown {
    final target = activeExam ?? nextExam;
    if (target == null) {
      return Duration.zero;
    }
    return target.remainingAt(now);
  }

  String get periodLabel {
    final target = activeExam ?? nextExam;
    if (target == null) {
      return '--:-- - --:--';
    }
    return target.windowText();
  }

  double get progress {
    final target = activeExam;
    if (target == null) {
      return 0;
    }
    return target.progressAt(now);
  }

  bool get isNearEnd {
    final target = activeExam;
    if (target == null) {
      return false;
    }
    final remaining = target.remainingAt(now);
    return remaining.inMinutes < 15 && remaining.inMinutes > 0;
  }

  Duration get minutesToEnd {
    final target = activeExam;
    if (target == null) {
      return Duration.zero;
    }
    return target.remainingAt(now);
  }

  void start() {
    if (_isDisposed || isRunning) {
      return;
    }
    _sortExams();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick();
    });
    _tick();
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void resume() {
    if (_isDisposed || isRunning) {
      return;
    }
    start();
  }

  void setNtpAddress(String address) {
    _ntpAddress = address.trim();
    notifyListeners();
  }

  void setMode(TimeSourceMode mode) {
    _mode = mode;
    _syncStatus = mode.label;
    if (_mode == TimeSourceMode.offlineManual) {
      _syncState = SyncState.idle;
      _syncErrorMessage = '';
    }
    notifyListeners();
  }

  void setMaxDriftStepMs(int value) {
    final clamped = value.clamp(20, 1000);
    if (_maxDriftStepMs == clamped) {
      return;
    }
    _maxDriftStepMs = clamped;
    notifyListeners();
  }

  Future<void> syncNow() async {
    await _syncOffset(manual: true);
  }

  String formatClock() {
    final t = now;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  String formatCountdown() {
    final d = countdown;
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _isDisposed = true;
    super.dispose();
  }

  void _tick() {
    _baseNow = _nowProvider();
    notifyListeners();

    if (_mode == TimeSourceMode.offlineManual || _syncing) {
      return;
    }
    if (!_shouldAttemptAutoSync()) {
      return;
    }
    unawaited(_syncOffset());
  }

  Future<void> _syncOffset({bool manual = false}) async {
    if (_mode == TimeSourceMode.offlineManual || _syncing) {
      return;
    }
    if (!manual && !_shouldAttemptAutoSync()) {
      return;
    }
    _lastAutoSyncAttempt = _baseNow;
    _syncing = true;
    _syncState = SyncState.syncing;
    _syncStatus = '同步中...';
    notifyListeners();
    try {
      final remoteNow = await _ntpService.fetchNetworkTime(
        mode: _mode,
        address: _ntpAddress,
      );
      final localNow = _nowProvider();
      final targetOffset = remoteNow.difference(localNow);

      final drift = targetOffset - _offset;
      final limited = _limitDriftStep(drift);
      _offset += limited;
      _lastAppliedDriftMs = limited.inMilliseconds;
      _lastSyncAt = localNow;
      _syncState = SyncState.success;
      _syncErrorMessage = '';
      _syncStatus = '已同步 ${_mode.label}';
      notifyListeners();
    } catch (error) {
      _syncState = SyncState.failure;
      _syncErrorMessage = error.toString();
      _syncStatus = '同步失败，已回退本地';
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  bool _shouldAttemptAutoSync() {
    final lastAttempt = _lastAutoSyncAttempt;
    if (lastAttempt == null) {
      return true;
    }
    return _baseNow.difference(lastAttempt) >= _autoSyncInterval;
  }

  Duration _limitDriftStep(Duration drift) {
    final sign = drift.isNegative ? -1 : 1;
    final absMs = drift.inMilliseconds.abs();
    final step = math.min(absMs, _maxDriftStepMs);
    return Duration(milliseconds: sign * step);
  }

  void _sortExams() {
    _exams.sort((a, b) => a.start.compareTo(b.start));
  }
}

class TimerScope extends InheritedNotifier<TimerController> {
  const TimerScope({
    super.key,
    required TimerController controller,
    required super.child,
  }) : super(notifier: controller);

  static TimerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TimerScope>();
    if (scope?.notifier == null) {
      throw StateError('TimerScope not found in widget tree.');
    }
    return scope!.notifier!;
  }

  static TimerController read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<TimerScope>();
    final widget = element?.widget;
    if (widget is! TimerScope || widget.notifier == null) {
      throw StateError('TimerScope not found in widget tree.');
    }
    return widget.notifier!;
  }
}
