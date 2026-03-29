import 'dart:convert';

import 'package:aeterna/core/config/config_manager.dart';
import 'package:aeterna/core/time/exam_models.dart';
import 'package:aeterna/core/time/timer_controller.dart';
import 'package:aeterna/shared/widgets/aeterna_reveal.dart';
import 'package:aeterna/shared/widgets/surface_card.dart';
import 'package:aeterna/theme/design_tokens.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

enum _DateMode { singleDay, multiDay }

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const String _defaultExamInfo = '认真考试，仔细检查';
  bool _editMode = true;
  bool _seededMeta = false;

  late DateTime _selectedDate;
  late final TextEditingController _examTitleController;
  late final TextEditingController _messageController;

  _DateMode _dateMode = _DateMode.singleDay;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _examTitleController = TextEditingController();
    _messageController = TextEditingController();
  }

  @override
  void dispose() {
    _examTitleController.dispose();
    _messageController.dispose();
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
            tooltip: '导入 JSON',
            onPressed: () => _importFromFile(controller),
            icon: const Icon(Icons.folder_open_outlined),
          ),
          IconButton(
            tooltip: '从友商导入 (EA2)',
            onPressed: () => _importFromFile(controller, examAwareOnly: true),
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            tooltip: '导出 JSON',
            onPressed: () => _exportToFile(controller),
            icon: const Icon(Icons.save_alt_outlined),
          ),
          IconButton(
            tooltip: '开启新计划',
            onPressed: () => _startNewPlan(controller),
            icon: const Icon(Icons.note_add_outlined),
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
            AeternaReveal(
              delay: const Duration(milliseconds: 50),
              child: _PlanMetaCard(
                editMode: _editMode,
                examTitleController: _examTitleController,
                messageController: _messageController,
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
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AeternaReveal(
                delay: const Duration(milliseconds: 120),
                child: _buildExamList(context, controller),
              ),
            ),
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
    _messageController.text =
      controller.exams
        .map((e) => e.message.trim())
        .firstWhere((m) => m.isNotEmpty, orElse: () => '');
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

        return AeternaReveal(
          delay: Duration(milliseconds: 40 + index * 35),
          child: SurfaceCard(
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
    final message = _messageController.text.trim();
    final now = DateTime.now();
    final start = _rangeStart ?? _dateOnly(now);
    final end = _dateMode == _DateMode.singleDay ? start : (_rangeEnd ?? start);

    controller.setExamMeta(examTitle: title, startDate: start, endDate: end);
    if (controller.exams.isNotEmpty) {
      final updated =
          controller.exams
              .map((slot) => slot.copyWith(message: message))
              .toList(growable: false);
      controller.replaceAllExams(updated);
    }

    setState(() {
      _rangeStart = start;
      _rangeEnd = end;
      _selectedDate = _clampDate(_selectedDate, start, end);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('考试基础信息已保存')));
  }

  Future<void> _exportToFile(TimerController controller) async {
    final json = ConfigManager.exportToJson(
      controller.exams,
      examTitle: controller.examTitle,
      startDate: controller.planStartDate,
      endDate: controller.planEndDate,
    );

    final safeTitle = controller.examTitle
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final now = DateTime.now();
    final suggestedName =
        'aeterna_${safeTitle.isEmpty ? 'schedule' : safeTitle}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.json';

    try {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null || !mounted) {
        return;
      }

      final file = XFile.fromData(
        utf8.encode(json),
        mimeType: 'application/json',
        name: suggestedName,
      );
      await file.saveTo(location.path);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出到: ${location.path}')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('导出失败，请重试')));
    }
  }

  Future<void> _importFromFile(
    TimerController controller, {
    bool examAwareOnly = false,
  }) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          if (examAwareOnly)
            const XTypeGroup(label: 'ExamAware2', extensions: ['ea2', 'json'])
          else
            const XTypeGroup(label: 'JSON', extensions: ['json', 'ea2']),
        ],
      );
      if (file == null || !mounted) {
        return;
      }

      final content = await file.readAsString();
      final plan = ConfigManager.importPlanFromJson(content);
      if (plan == null) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('配置导入失败：文件内容无效')));
        return;
      }

      if (examAwareOnly &&
          !plan.exams.any((e) => e.message.trim().isNotEmpty)) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该文件不是有效的友商 EA2 格式或缺少 message 字段')),
        );
        return;
      }

      controller.setExamMeta(
        examTitle: plan.examTitle,
        startDate: plan.startDate,
        endDate: plan.endDate,
      );
      controller.replaceAllExams(plan.exams);

      setState(() {
        _examTitleController.text = plan.examTitle;
        _messageController.text =
            plan.exams
                .map((e) => e.message.trim())
                .firstWhere((m) => m.isNotEmpty, orElse: () => '');
        _rangeStart = plan.startDate;
        _rangeEnd = plan.endDate;
        _selectedDate = _clampDate(_selectedDate, plan.startDate, plan.endDate);
        _dateMode = _isSameDate(plan.startDate, plan.endDate)
            ? _DateMode.singleDay
            : _DateMode.multiDay;
      });

      if (!mounted) {
        return;
      }
      final examCount = plan.exams.length;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(
        content: Text('✓ 导入成功: ${file.name} ($examCount科考试)'),
        duration: const Duration(seconds: 3),
      ));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置导入失败，请重试')));
    }
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
      final metaMessage = _messageController.text.trim();
      controller.addExam(
        result.copyWith(
          message: metaMessage.isEmpty ? _defaultExamInfo : metaMessage,
        ),
      );
    } else {
      final metaMessage = _messageController.text.trim();
      controller.updateExam(
        existingIndex,
        result.copyWith(
          message: metaMessage.isEmpty ? _defaultExamInfo : metaMessage,
        ),
      );
    }
  }

  Future<void> _startNewPlan(TimerController controller) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开启新计划'),
        content: const Text('将清空当前科目并创建一个全新的计划，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    final now = DateTime.now();
    final today = _dateOnly(now);
    final newTitle = '新计划 ${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    controller.setExamMeta(examTitle: newTitle, startDate: today, endDate: today);
    controller.replaceAllExams(const <ExamSlot>[]);

    setState(() {
      _examTitleController.text = newTitle;
      _messageController.text = '';
      _rangeStart = today;
      _rangeEnd = today;
      _selectedDate = today;
      _dateMode = _DateMode.singleDay;
      _editMode = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已开启新计划，可立即新增科目')));
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
    required this.messageController,
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
  final TextEditingController messageController;
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
          TextField(
            controller: messageController,
            enabled: editMode,
            decoration: const InputDecoration(
              labelText: '考试信息（可选）',
              hintText: '例如：高二年级 / 班级名称 / 其他备注',
            ),
            maxLines: 1,
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
  late List<ExamMaterial> _materials;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _subjectController = TextEditingController(text: existing?.subject ?? '');
    _startTime = _toTime(existing?.start ?? DateTime.now());
    _endTime = _toTime(
      existing?.end ?? DateTime.now().add(const Duration(hours: 1)),
    );
    _materials = List.of(existing?.materials ?? []);
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
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
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
              const SizedBox(height: 20),
              // 材料管理部分
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '考试材料',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton.filled(
                    onPressed: _addMaterial,
                    icon: const Icon(Icons.add),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_materials.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '暂无材料',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _materials.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final material = _materials[index];
                    return _MaterialRow(
                      material: material,
                      onEdit: () => _editMaterial(index),
                      onDelete: () => _deleteMaterial(index),
                    );
                  },
                ),
            ],
          ),
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

  void _addMaterial() {
    showDialog<ExamMaterial>(
      context: context,
      builder: (_) => _MaterialEditDialog(
        material: null,
      ),
    ).then((material) {
      if (material != null) {
        setState(() {
          _materials.add(material);
        });
      }
    });
  }

  void _editMaterial(int index) {
    showDialog<ExamMaterial>(
      context: context,
      builder: (_) => _MaterialEditDialog(
        material: _materials[index],
      ),
    ).then((material) {
      if (material != null) {
        setState(() {
          _materials[index] = material;
        });
      }
    });
  }

  void _deleteMaterial(int index) {
    setState(() {
      _materials.removeAt(index);
    });
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
    ).pop(ExamSlot(
      subject: subject,
      start: start,
      end: end,
      materials: _materials,
      message: widget.existing?.message ?? '',
    ));
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

/// 材料行小部件
class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.onEdit,
    required this.onDelete,
  });

  final ExamMaterial material;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${material.quantity}${material.unit}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: '删除',
          ),
        ],
      ),
    );
  }
}

/// 材料编辑对话框
class _MaterialEditDialog extends StatefulWidget {
  const _MaterialEditDialog({required this.material});

  final ExamMaterial? material;

  @override
  State<_MaterialEditDialog> createState() => _MaterialEditDialogState();
}

class _MaterialEditDialogState extends State<_MaterialEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _unitController;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    _nameController = TextEditingController(text: material?.name ?? '');
    _quantityController = TextEditingController(text: (material?.quantity ?? 1).toString());
    _unitController = TextEditingController(text: material?.unit ?? '份');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.material == null ? '新增材料' : '编辑材料'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '材料名称'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(labelText: '数量'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _unitController,
                    decoration: const InputDecoration(labelText: '单位'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      return;
    }

    final quantity = int.tryParse(_quantityController.text) ?? 1;
    final unit = _unitController.text.trim().isEmpty ? '份' : _unitController.text.trim();

    Navigator.of(context).pop(ExamMaterial(
      name: name,
      quantity: quantity,
      unit: unit,
    ));
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
