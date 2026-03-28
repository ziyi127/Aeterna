import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:flutter/material.dart';

enum _DateMode { singleDay, multiDay }

class ScheduleViewerPage extends StatefulWidget {
  const ScheduleViewerPage({super.key});

  @override
  State<ScheduleViewerPage> createState() => _ScheduleViewerPageState();
}

class _ScheduleViewerPageState extends State<ScheduleViewerPage> {
  bool _editMode = true;
  bool _seededMeta = false;

  late DateTime _selectedDate;
  late final TextEditingController _examTitleController;

  _DateMode _dateMode = _DateMode.singleDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _examTitleController = TextEditingController();
  }

  @override
  void dispose() {
    _examTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = TimerScope.of(context);
    final width = MediaQuery.sizeOf(context).width;

    _seedFromController(controller);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editMode ? '计划编辑器 Plan Editor' : '任务清单 Schedule Viewer'),
        actions: [
          IconButton(
            tooltip: _editMode ? '切换到查看' : '切换到编辑',
            onPressed: () => setState(() => _editMode = !_editMode),
            icon: Icon(
              _editMode ? Icons.visibility_outlined : Icons.edit_outlined,
            ),
          ),
          IconButton(
            tooltip: '导出 JSON',
            onPressed: () => _showExportDialog(context, controller),
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: '导入 JSON',
            onPressed: () => _showImportDialog(context, controller),
            icon: const Icon(Icons.upload_outlined),
          ),
        ],
      ),
      floatingActionButton: _editMode
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(controller),
              icon: const Icon(Icons.add),
              label: const Text('新增科目'),
            )
          : null,
      body: Padding(
        padding: AeternaTokens.pagePaddingFor(width),
        child: Column(
          children: [
            _PlanMetaCard(
              editMode: _editMode,
              examTitleController: _examTitleController,
              dateMode: _dateMode,
              rangeStart: _rangeStart,
              rangeEnd: _rangeEnd,
              selectedDate: _selectedDate,
              onDateModeChanged: (mode) => setState(() => _dateMode = mode),
              onPickRangeStart: () => _pickRangeDate(isStart: true),
              onPickRangeEnd: () => _pickRangeDate(isStart: false),
              onPickSelectedDate: () => _pickSelectedDate(),
              onSaveMeta: () => _saveMeta(controller),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildExamList(context, controller)),
          ],
        ),
      ),
    );
  }

  void _seedFromController(TimerController controller) {
    if (_seededMeta) {
      return;
    }

    final now = DateTime.now();
    final fallbackDate = DateTime(now.year, now.month, now.day);

    final start =
        controller.planStartDate ??
        _inferStartDate(controller.exams) ??
        fallbackDate;
    final end =
        controller.planEndDate ?? _inferEndDate(controller.exams) ?? start;

    _examTitleController.text = controller.examTitle;
    _rangeStart = start;
    _rangeEnd = end;
    _selectedDate = _clampDate(_selectedDate, start, end);
    _dateMode = _isSameDate(start, end)
        ? _DateMode.singleDay
        : _DateMode.multiDay;

    _seededMeta = true;
  }

  Widget _buildExamList(BuildContext context, TimerController controller) {
    final width = MediaQuery.sizeOf(context).width;
    final selectedDateOnly = _dateOnly(_selectedDate);

    final filteredExams = controller.exams.where((exam) {
      final examDate = _dateOnly(exam.start);
      return examDate == selectedDateOnly;
    }).toList();

    if (filteredExams.isEmpty) {
      return Center(
        child: Text('该日期没有科目安排', style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.separated(
      itemCount: filteredExams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final slot = filteredExams[index];
        final state = slot.stateAt(controller.now);
        final originalIndex = controller.exams.indexOf(slot);

        return SurfaceCard(
          child: ListTile(
            minTileHeight: AeternaTokens.touchMinHeight,
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: width < 700 ? 90 : 120,
              child: Text(
                slot.windowText(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            title: Text(
              slot.subject,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: _editMode ? const Text('可编辑：点击铅笔修改') : null,
            trailing: _editMode
                ? _EditActions(
                    onEdit: () => _openEditor(
                      controller,
                      existingIndex: originalIndex,
                      existing: slot,
                    ),
                    onDelete: () => controller.removeExam(originalIndex),
                  )
                : _StateBadge(state: state),
          ),
        );
      },
    );
  }

  Future<void> _pickRangeDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_rangeStart ?? _dateOnly(now))
        : (_rangeEnd ?? _rangeStart ?? _dateOnly(now));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2099),
    );
    if (picked == null) {
      return;
    }

    setState(() {
      if (isStart) {
        _rangeStart = _dateOnly(picked);
        _rangeEnd ??= _rangeStart;
        if (_rangeEnd!.isBefore(_rangeStart!)) {
          _rangeEnd = _rangeStart;
        }
      } else {
        _rangeEnd = _dateOnly(picked);
        _rangeStart ??= _rangeEnd;
        if (_rangeEnd!.isBefore(_rangeStart!)) {
          _rangeStart = _rangeEnd;
        }
      }
      _selectedDate = _clampDate(_selectedDate, _rangeStart!, _rangeEnd!);
      _dateMode = _isSameDate(_rangeStart!, _rangeEnd!)
          ? _DateMode.singleDay
          : _DateMode.multiDay;
    });
  }

  Future<void> _pickSelectedDate() async {
    final now = DateTime.now();
    final start = _rangeStart ?? _dateOnly(now);
    final end = _rangeEnd ?? start;
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: start,
      lastDate: end,
    );
    if (picked == null) {
      return;
    }
    setState(() => _selectedDate = _dateOnly(picked));
  }

  void _saveMeta(TimerController controller) {
    final title = _examTitleController.text.trim();
    final now = DateTime.now();
    final start = _rangeStart ?? _dateOnly(now);
    final end = _dateMode == _DateMode.singleDay ? start : (_rangeEnd ?? start);

    controller.setExamMeta(examTitle: title, startDate: start, endDate: end);

    setState(() {
      _rangeStart = start;
      _rangeEnd = end;
      _selectedDate = _clampDate(_selectedDate, start, end);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('考试基础信息已保存')));
  }

  void _showExportDialog(BuildContext context, TimerController controller) {
    final json = ConfigManager.exportToJson(
      controller.exams,
      examTitle: controller.examTitle,
      startDate: controller.planStartDate,
      endDate: controller.planEndDate,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出配置'),
        content: SingleChildScrollView(
          child: Text(json, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context, TimerController controller) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入配置'),
        content: TextField(
          controller: textController,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '粘贴 JSON 配置内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final plan = ConfigManager.importPlanFromJson(
                textController.text,
              );
              if (plan != null) {
                controller.setExamMeta(
                  examTitle: plan.examTitle,
                  startDate: plan.startDate,
                  endDate: plan.endDate,
                );
                controller.replaceAllExams(plan.exams);

                setState(() {
                  _examTitleController.text = plan.examTitle;
                  _rangeStart = plan.startDate;
                  _rangeEnd = plan.endDate;
                  _selectedDate = _clampDate(
                    _selectedDate,
                    plan.startDate,
                    plan.endDate,
                  );
                  _dateMode = _isSameDate(plan.startDate, plan.endDate)
                      ? _DateMode.singleDay
                      : _DateMode.multiDay;
                });

                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('配置导入成功')));
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('配置导入失败')));
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    TimerController controller, {
    int? existingIndex,
    ExamSlot? existing,
  }) async {
    final date = existing != null ? _dateOnly(existing.start) : _selectedDate;
    final result = await showDialog<ExamSlot>(
      context: context,
      builder: (_) => _ExamEditDialog(existing: existing, date: date),
    );

    if (!mounted || result == null) {
      return;
    }

    final start = _rangeStart;
    final end = _rangeEnd;
    if (start != null && end != null) {
      final slotDate = _dateOnly(result.start);
      if (slotDate.isBefore(start) || slotDate.isAfter(end)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('科目日期超出考试日期范围，请先调整范围')));
        return;
      }
    }

    if (existingIndex == null) {
      controller.addExam(result);
    } else {
      controller.updateExam(existingIndex, result);
    }
  }

  DateTime? _inferStartDate(List<ExamSlot> exams) {
    if (exams.isEmpty) {
      return null;
    }
    var min = exams.first.start;
    for (final e in exams) {
      if (e.start.isBefore(min)) {
        min = e.start;
      }
    }
    return _dateOnly(min);
  }

  DateTime? _inferEndDate(List<ExamSlot> exams) {
    if (exams.isEmpty) {
      return null;
    }
    var max = exams.first.end;
    for (final e in exams) {
      if (e.end.isAfter(max)) {
        max = e.end;
      }
    }
    return _dateOnly(max);
  }

  DateTime _clampDate(DateTime value, DateTime start, DateTime end) {
    final dateOnly = _dateOnly(value);
    if (dateOnly.isBefore(start)) {
      return start;
    }
    if (dateOnly.isAfter(end)) {
      return end;
    }
    return dateOnly;
  }

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _PlanMetaCard extends StatelessWidget {
  const _PlanMetaCard({
    required this.editMode,
    required this.examTitleController,
    required this.dateMode,
    required this.rangeStart,
    required this.rangeEnd,
    required this.selectedDate,
    required this.onDateModeChanged,
    required this.onPickRangeStart,
    required this.onPickRangeEnd,
    required this.onPickSelectedDate,
    required this.onSaveMeta,
  });

  final bool editMode;
  final TextEditingController examTitleController;
  final _DateMode dateMode;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final DateTime selectedDate;
  final ValueChanged<_DateMode> onDateModeChanged;
  final VoidCallback onPickRangeStart;
  final VoidCallback onPickRangeEnd;
  final VoidCallback onPickSelectedDate;
  final VoidCallback onSaveMeta;

  @override
  Widget build(BuildContext context) {
    final start = rangeStart;
    final end = rangeEnd;

    return SurfaceCard(
      style: SurfaceCardStyle.elevated,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('考试基本信息', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          TextField(
            controller: examTitleController,
            enabled: editMode,
            decoration: const InputDecoration(
              labelText: '考试名称',
              hintText: '例如：XX学校3月月考 / XX学校期末考',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_DateMode>(
            segments: const [
              ButtonSegment(value: _DateMode.singleDay, label: Text('单天')),
              ButtonSegment(value: _DateMode.multiDay, label: Text('多天')),
            ],
            selected: {dateMode},
            onSelectionChanged: editMode
                ? (selection) => onDateModeChanged(selection.first)
                : null,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: editMode ? onPickRangeStart : null,
                child: Text('开始日: ${_fmtDate(start)}'),
              ),
              if (dateMode == _DateMode.multiDay)
                FilledButton.tonal(
                  onPressed: editMode ? onPickRangeEnd : null,
                  child: Text('结束日: ${_fmtDate(end)}'),
                ),
              FilledButton.tonal(
                onPressed: onPickSelectedDate,
                child: Text('当前编辑日: ${_fmtDate(selectedDate)}'),
              ),
              if (editMode)
                FilledButton(
                  onPressed: onSaveMeta,
                  child: const Text('保存考试信息'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) {
      return '--';
    }
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _EditActions extends StatelessWidget {
  const _EditActions({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      children: [
        IconButton(
          tooltip: '编辑',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: '删除',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }
}

class _ExamEditDialog extends StatefulWidget {
  const _ExamEditDialog({this.existing, required this.date});

  final ExamSlot? existing;
  final DateTime date;

  @override
  State<_ExamEditDialog> createState() => _ExamEditDialogState();
}

class _ExamEditDialogState extends State<_ExamEditDialog> {
  late final TextEditingController _subjectController;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _subjectController = TextEditingController(text: existing?.subject ?? '');
    _startTime = _toTime(existing?.start ?? DateTime.now());
    _endTime = _toTime(
      existing?.end ?? DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  void dispose() {
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '新增科目' : '编辑科目'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('日期: ${_fmtDate(widget.date)}'),
            const SizedBox(height: 10),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(labelText: '科目名'),
            ),
            const SizedBox(height: 14),
            _TimeRow(
              label: '开始时间',
              value: _fmt(_startTime),
              onTap: () => _pickTime(true),
            ),
            const SizedBox(height: 10),
            _TimeRow(
              label: '结束时间',
              value: _fmt(_endTime),
              onTap: () => _pickTime(false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) {
      return;
    }
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  void _save() {
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      return;
    }

    final base = DateTime(widget.date.year, widget.date.month, widget.date.day);
    final start = DateTime(
      base.year,
      base.month,
      base.day,
      _startTime.hour,
      _startTime.minute,
    );
    var end = DateTime(
      base.year,
      base.month,
      base.day,
      _endTime.hour,
      _endTime.minute,
    );

    if (!end.isAfter(start)) {
      end = start.add(const Duration(minutes: 45));
    }

    Navigator.of(
      context,
    ).pop(ExamSlot(subject: subject, start: start, end: end));
  }

  TimeOfDay _toTime(DateTime dt) => TimeOfDay(hour: dt.hour, minute: dt.minute);

  String _fmt(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        FilledButton.tonal(onPressed: onTap, child: Text(value)),
      ],
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.state});

  final ExamState state;

  @override
  Widget build(BuildContext context) {
    final color = state.color(Theme.of(context).colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.18),
      ),
      child: Text(
        state.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
