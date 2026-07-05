import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/calendar_date.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/platform/preparation_reminder_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../../domain/entities/preparation_template.dart';
import '../../../domain/repositories/preparation_plan_repository.dart';
import '../../../domain/services/preparation_scheduler.dart';
import '../providers/preparation_providers.dart';
import '../providers/preparation_reminder_providers.dart';
import '../widgets/assistant_drawer.dart';
import '../widgets/preparation_anchor_bar.dart';
import '../widgets/preparation_countdown.dart';
import '../widgets/preparation_date_picker.dart';
import '../widgets/preparation_deadline_card.dart';
import '../widgets/preparation_phase_timeline.dart';
import '../widgets/preparation_task_list.dart';

/// 目标日期变更时的重排策略（spec §4.5 双段模型）。
///
/// 抽取为纯静态方法以便单元测试覆盖提交型「仅重排前置阶段、defense_prep 不动」
/// 这一不变量——直接驱动原生 `showDatePicker` 在 widget 测试里很脆弱，无法稳定
/// 覆盖该分支。
class PreparationPlanDetailRescheduler {
  PreparationPlanDetailRescheduler._();

  /// 在目标日期变更为 [newTargetDate] 后重排 [plan] 的阶段与未完成任务。
  ///
  /// - 提交型（`timelineType == submission`）：只重排 `key != 'defense_prep'`
  ///   的前置阶段；`defense_prep` 阶段（含其任务的 dueDate）原样保留，仍落在
  ///   [targetDate+1, defenseDate] 区间。返回的 `eventEndDate` 不变。
  /// - 窗口型（`eventWindow`）：重排全部阶段；若新 `targetDate` 晚于
  ///   `eventEndDate`，将 `eventEndDate` 同步抬到 `targetDate` 以维持
  ///   「比赛日 <= 结束日」。
  ///
  /// 完成态任务保留原 dueDate 与 completedAt；未完成任务 dueDate 重排到所属阶段
  /// 的新 endDate（钳制到 [today, newTargetDate]）。
  ///
  /// 返回 `(phases, eventEndDate)`，由调用方组装新的 [PreparationPlan]。
  static ({List<PreparationPhase> phases, DateTime? eventEndDate})
  rescheduleForTargetDateChange({
    required PreparationPlan plan,
    required DateTime newTargetDate,
    required DateTime today,
  }) {
    final isSubmission =
        plan.timelineType == CompetitionTimelineType.submission;
    if (isSubmission) {
      final pre = plan.phases.where((p) => p.key != 'defense_prep').toList();
      final defense = plan.phases
          .where((p) => p.key == 'defense_prep')
          .toList();
      final rescheduledPre = _reschedulePhases(
        phases: pre,
        today: today,
        newTargetDate: newTargetDate,
      );
      return (
        phases: [...rescheduledPre, ...defense],
        eventEndDate: plan.eventEndDate,
      );
    }
    final newPhases = _reschedulePhases(
      phases: plan.phases,
      today: today,
      newTargetDate: newTargetDate,
    );
    DateTime? newEventEndDate = plan.eventEndDate;
    final ev = plan.eventEndDate;
    if (ev != null && newTargetDate.isAfter(ev)) {
      newEventEndDate = newTargetDate;
    }
    return (phases: newPhases, eventEndDate: newEventEndDate);
  }

  /// Re-distribute the new total window across phases proportionally to their
  /// current relative durations, then move incomplete tasks' dueDate to their
  /// phase's new endDate (clamped). Completed tasks keep dueDate + completedAt.
  ///
  /// We use [PreparationScheduler.schedule] for phase boundary recomputation:
  /// phase weights are derived from current durations (endDate-startDate+1,
  /// clamped to >=1). The scheduler guarantees contiguous, non-overlapping
  /// segments covering [today, newTargetDate] exactly.
  static List<PreparationPhase> _reschedulePhases({
    required List<PreparationPhase> phases,
    required DateTime today,
    required DateTime newTargetDate,
  }) {
    if (phases.isEmpty) return phases;

    final templatePhases = phases
        .map(
          (p) => PreparationTemplatePhase(
            key: p.key,
            title: p.title,
            weight: _durationDays(p.startDate, p.endDate).toDouble(),
            requiredTasks: const [],
            optionalTasks: const [],
          ),
        )
        .toList();

    final segments = PreparationScheduler.schedule(
      phases: templatePhases,
      today: today,
      targetDate: newTargetDate,
    );

    // Map segments back to phases by index (scheduler preserves order;
    // merging only happens when window is too tight — keys would join '+',
    // but we still map by index to the original phase list because merging
    // shrinks the segment count, in which case we attach remaining phases to
    // the last segment to avoid index OOB).
    final newPhases = <PreparationPhase>[];
    for (var i = 0; i < phases.length; i++) {
      final seg = segments.length > i ? segments[i] : segments.last;
      final newStart = seg.startDate;
      final newEnd = seg.endDate;
      final newTasks = phases[i].tasks.map((t) {
        if (t.completed) return t;
        final due = newEnd.isBefore(today)
            ? today
            : (newEnd.isAfter(newTargetDate) ? newTargetDate : newEnd);
        return t.copyWith(dueDate: due);
      }).toList();
      newPhases.add(
        phases[i].copyWith(
          startDate: newStart,
          endDate: newEnd,
          tasks: newTasks,
        ),
      );
    }
    return newPhases;
  }

  static int _durationDays(DateTime start, DateTime end) {
    final d = end.difference(start).inDays + 1;
    return d < 1 ? 1 : d;
  }
}

/// 备赛计划详情页（spec §7.4）。
///
/// 顶部倒计时 + 总进度 + 当前阶段 + 紧/超负荷警示；中部阶段时间轴；
/// 底部任务清单（按阶段分组，可勾选/编辑/删除/添加）。
/// 操作：修改目标日期（重算未完成任务 dueDate，保留已完成）、归档、删除。
class PreparationPlanDetailPage extends ConsumerStatefulWidget {
  const PreparationPlanDetailPage({super.key, required this.planId});

  final String planId;

  @override
  ConsumerState<PreparationPlanDetailPage> createState() =>
      _PreparationPlanDetailPageState();
}

class _PreparationPlanDetailPageState
    extends ConsumerState<PreparationPlanDetailPage> {
  PreparationPlan? _plan;
  bool _loading = true;
  String? _addingLabel;

  @override
  void initState() {
    super.initState();
    // 首帧后异步加载，避免在 build 期间同步读取仓库。
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    final repo = ref.read(preparationPlanRepositoryProvider);
    final plan = repo.findById(widget.planId);
    if (!mounted) return;
    setState(() {
      _plan = plan;
      _loading = false;
    });
  }

  PreparationPlanRepository get _repo =>
      ref.read(preparationPlanRepositoryProvider);

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Widget _backButton() => IconButton(
    tooltip: '返回',
    icon: const Icon(Icons.arrow_back),
    onPressed: _handleBack,
  );

  void _handleBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    context.go('/preparation-plans');
  }

  // 阶段允许的截止日期区间（spec §4.5 双段模型）：
  // - defense_prep 阶段：[targetDate+1, defenseDate]（答辩准备在提交后）。
  // - 其它阶段：[today, targetDate]。
  // 当 defenseDate 缺省（不应出现 defense_prep）时退化为 [today, targetDate]。
  ({DateTime first, DateTime last}) _phaseDateRange(
    PreparationPlan plan,
    String phaseKey,
  ) {
    if (phaseKey == 'defense_prep' && plan.defenseDate != null) {
      final first = plan.targetDate.add(const Duration(days: 1));
      final last = plan.defenseDate!.isBefore(first)
          ? first
          : plan.defenseDate!;
      return (first: first, last: last);
    }
    final last = plan.targetDate.isBefore(_today) ? _today : plan.targetDate;
    return (first: _today, last: last);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final plan = _plan;
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(leading: _backButton(), title: const Text('计划详情')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search_off, size: 48, color: AppColors.inkFaint),
              const SizedBox(height: 12),
              const Text(
                '未找到该计划',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _handleBack, child: const Text('返回')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: _backButton(),
        title: Text(plan.competition.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onPressed: () => _openPlanMoreMenu(plan),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          PreparationCountdown(plan: plan, today: _today),
          const SizedBox(height: 8),
          PreparationAnchorBar(plan: plan),
          const SizedBox(height: 12),
          PreparationDeadlineCard(
            label: '报名截止',
            date: plan.registrationDeadline,
            adding: _addingLabel == '报名截止',
            onAddToCalendar: () =>
                _addToCalendar(label: '报名截止', date: plan.registrationDeadline),
            onEditDate: () => _editRegistrationDeadline(),
          ),
          const SizedBox(height: 8),
          PreparationDeadlineCard(
            label: plan.timelineType == CompetitionTimelineType.submission
                ? '提交截止'
                : '比赛开始',
            date: plan.targetDate,
            adding:
                _addingLabel ==
                (plan.timelineType == CompetitionTimelineType.submission
                    ? '提交截止'
                    : '比赛开始'),
            onAddToCalendar: () => _addToCalendar(
              label: plan.timelineType == CompetitionTimelineType.submission
                  ? '提交截止'
                  : '比赛开始',
              date: plan.targetDate,
            ),
          ),
          const SizedBox(height: 12),
          PreparationPhaseTimeline(plan: plan, today: _today),
          const SizedBox(height: 12),
          PreparationTaskList(
            plan: plan,
            onToggleTask: _toggleTask,
            onEditTask: _editTask,
            onDeleteTask: _deleteTask,
            onAddTask: _addTask,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'preparation_assistant_${plan.id}',
        tooltip: '竞航小助手',
        backgroundColor: AppColors.indigo,
        foregroundColor: Colors.white,
        onPressed: () => _openAssistant(plan),
        child: const Icon(Icons.auto_awesome),
      ),
    );
  }

  void _openAssistant(PreparationPlan plan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        clipBehavior: Clip.antiAlias,
        child: PreparationAssistantDrawer(planId: plan.id, plan: plan),
      ),
    );
  }

  void _openPlanMoreMenu(PreparationPlan plan) {
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlanMoreSheet(plan: plan),
    ).then((v) {
      if (v == 'targetDate') {
        _changeTargetDate(plan);
      } else if (v == 'archive') {
        _confirmArchive(plan);
      } else if (v == 'delete') {
        _confirmDelete(plan);
      }
    });
  }

  // ── 任务完成 / 撤销 ────────────────────────────────────────────────────
  Future<void> _toggleTask(int phaseIndex, int taskIndex) async {
    final plan = _plan;
    if (plan == null) return;
    final task = plan.phases[phaseIndex].tasks[taskIndex];
    final newCompletedAt = task.completed ? null : DateTime.now();
    final updatedTask = task.copyWith(completedAt: newCompletedAt);
    final updatedPhase = plan.phases[phaseIndex].copyWith(
      tasks: _replaceAt(plan.phases[phaseIndex].tasks, taskIndex, updatedTask),
    );
    final updatedPlan = plan.copyWith(
      phases: _replaceAt(plan.phases, phaseIndex, updatedPhase),
    );
    Haptics.light();
    await _saveAndRefresh(updatedPlan);
  }

  // ── 添加任务（每阶段 userAdded） ────────────────────────────────────────
  Future<void> _addTask(int phaseIndex) async {
    final plan = _plan;
    if (plan == null) return;
    final phase = plan.phases[phaseIndex];
    final range = _phaseDateRange(plan, phase.key);
    final result = await showDialog<_TaskEditResult>(
      context: context,
      builder: (_) => _TaskEditDialog(
        initialTitle: '',
        initialNote: '',
        initialDueDate: phase.endDate,
        firstDate: range.first,
        lastDate: range.last,
      ),
    );
    if (result == null) return;
    final newTask = PreparationTask(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      title: result.title,
      kind: PreparationTaskKind.userAdded,
      estimatedHours: 1,
      dueDate: result.dueDate,
      note: result.note,
    );
    final updatedPhase = phase.copyWith(tasks: [...phase.tasks, newTask]);
    final updatedPlan = plan.copyWith(
      phases: _replaceAt(plan.phases, phaseIndex, updatedPhase),
    );
    Haptics.selection();
    await _saveAndRefresh(updatedPlan);
  }

  // ── 编辑任务（title/note/dueDate） ──────────────────────────────────────
  Future<void> _editTask(int phaseIndex, int taskIndex) async {
    final plan = _plan;
    if (plan == null) return;
    final task = plan.phases[phaseIndex].tasks[taskIndex];
    final range = _phaseDateRange(plan, plan.phases[phaseIndex].key);
    final result = await showDialog<_TaskEditResult>(
      context: context,
      builder: (_) => _TaskEditDialog(
        initialTitle: task.title,
        initialNote: task.note ?? '',
        initialDueDate: task.dueDate,
        firstDate: range.first,
        lastDate: range.last,
      ),
    );
    if (result == null) return;
    final updatedTask = task.copyWith(
      title: result.title,
      note: result.note,
      dueDate: result.dueDate,
    );
    final updatedPhase = plan.phases[phaseIndex].copyWith(
      tasks: _replaceAt(plan.phases[phaseIndex].tasks, taskIndex, updatedTask),
    );
    final updatedPlan = plan.copyWith(
      phases: _replaceAt(plan.phases, phaseIndex, updatedPhase),
    );
    Haptics.selection();
    await _saveAndRefresh(updatedPlan);
  }

  // ── 删除任务（必做不可删，由 UI 不渲染删除按钮保证） ────────────────────
  Future<void> _deleteTask(int phaseIndex, int taskIndex) async {
    final plan = _plan;
    if (plan == null) return;
    final task = plan.phases[phaseIndex].tasks[taskIndex];
    if (task.kind == PreparationTaskKind.required) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${task.title}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final newTasks = List<PreparationTask>.from(plan.phases[phaseIndex].tasks)
      ..removeAt(taskIndex);
    final updatedPhase = plan.phases[phaseIndex].copyWith(tasks: newTasks);
    final updatedPlan = plan.copyWith(
      phases: _replaceAt(plan.phases, phaseIndex, updatedPhase),
    );
    Haptics.warning();
    await _saveAndRefresh(updatedPlan);
  }

  // ── 修改目标日期：仅重算未完成任务 dueDate，保留完成态 + 备注 ──────────
  //
  // 实际的重排分支（提交型仅前置 / 窗口型全段 + eventEndDate 抬升）与按比例重排
  // 已抽取为纯单元 [PreparationPlanDetailRescheduler]，便于单元测试直接覆盖
  // defense_prep 不变这一不变量。这里仅负责弹 DatePicker 并落库。
  Future<void> _changeTargetDate(PreparationPlan plan) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sel = await showPreparationDatePicker(
      context: context,
      mode: PreparationDatePickerMode.single,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: today.add(const Duration(days: 365 * 3)),
      initial: PreparationDateSelection(single: plan.targetDate),
    );
    final picked = sel?.single;
    if (picked == null || !mounted) return;

    final result =
        PreparationPlanDetailRescheduler.rescheduleForTargetDateChange(
          plan: plan,
          newTargetDate: picked,
          today: today,
        );
    final shouldClearRegistrationDeadline =
        plan.registrationDeadline != null &&
        !plan.registrationDeadline!.isBefore(picked);
    var updatedPlan = plan.copyWith(
      targetDate: picked,
      eventEndDate: result.eventEndDate,
      phases: result.phases,
    );
    if (shouldClearRegistrationDeadline) {
      updatedPlan = updatedPlan.copyWith(registrationDeadline: null);
    }
    await _saveAndRefresh(updatedPlan);
    if (!mounted) return;
    final message = shouldClearRegistrationDeadline
        ? '目标日期已更新，报名截止已清空，请重新选择'
        : '目标日期已更新，未完成任务已重新排期';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 归档 / 删除 plan（二次确认） ────────────────────────────────────────
  Future<void> _confirmArchive(PreparationPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('归档计划'),
        content: const Text('归档后该计划将不再出现在进行中列表，确认归档？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('归档'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.archive(plan.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _confirmDelete(PreparationPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除计划'),
        content: const Text('删除后无法恢复，确认删除该计划？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.delete(plan.id);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  // ── 加入系统日历 / 编辑报名截止 ─────────────────────────────────────────
  Future<void> _addToCalendar({
    required String label,
    required DateTime? date,
  }) async {
    if (date == null || _addingLabel != null) return;
    setState(() => _addingLabel = label);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final event = CalendarDeadlineEvent(
        title: '${_plan!.competition.name}·$label',
        isoDay: CalendarDate.toIsoDay(date),
        notes: '由 SchoNavi 备赛计划添加',
      );
      final result = await ref
          .read(preparationReminderPlatformProvider)
          .addDeadlineEvent(event);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_calendarResultMessage(result))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('加入日历失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _addingLabel = null);
    }
  }

  String _calendarResultMessage(CalendarAddResult r) => switch (r) {
    CalendarAddResult.success => '已加入系统日历',
    CalendarAddResult.fallbackIntentLaunched => '已打开日历 App，请确认保存',
    CalendarAddResult.unsupported => '当前设备不支持，请手动添加',
    CalendarAddResult.failed => '加入日历失败，请稍后重试',
  };

  Future<void> _editRegistrationDeadline() async {
    final plan = _plan;
    if (plan == null) return;
    final today = _today;
    final picked = await showPreparationDatePicker(
      context: context,
      mode: PreparationDatePickerMode.single,
      firstDate: today.add(const Duration(days: 1)),
      lastDate: plan.targetDate.subtract(const Duration(days: 1)),
      initial: PreparationDateSelection(
        single: plan.registrationDeadline ?? plan.targetDate,
      ),
    );
    final value = picked?.single;
    if (value == null) return; // 取消
    // 选到的日期若 >= targetDate 视为非法，直接忽略（DatePicker 已约束 lastDate）
    if (!value.isBefore(plan.targetDate)) return;
    final updated = plan.copyWith(registrationDeadline: value);
    await _saveAndRefresh(updated);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('报名截止已更新')));
  }

  // ── 保存 + 本地刷新 ─────────────────────────────────────────────────────
  Future<void> _saveAndRefresh(PreparationPlan plan) async {
    final saved = await _repo.save(plan);
    if (!mounted) return;
    setState(() => _plan = saved);
  }

  // ── 工具：列表不可变替换 ────────────────────────────────────────────────
  List<T> _replaceAt<T>(List<T> list, int index, T value) {
    final copy = List<T>.from(list);
    copy[index] = value;
    return copy;
  }
}

/// 任务编辑/新增对话框结果。
class _TaskEditResult {
  const _TaskEditResult({
    required this.title,
    required this.note,
    required this.dueDate,
  });
  final String title;
  final String note;
  final DateTime dueDate;
}

class _TaskEditDialog extends StatefulWidget {
  const _TaskEditDialog({
    required this.initialTitle,
    required this.initialNote,
    required this.initialDueDate,
    required this.firstDate,
    required this.lastDate,
  });

  final String initialTitle;
  final String initialNote;
  final DateTime initialDueDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_TaskEditDialog> createState() => _TaskEditDialogState();
}

class _TaskEditDialogState extends State<_TaskEditDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _noteCtrl;
  late DateTime _dueDate;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _noteCtrl = TextEditingController(text: widget.initialNote);
    // Defensive: guarantee lastDate >= firstDate so showDatePicker's
    // `!lastDate.isBefore(firstDate)` assertion holds even when the plan is
    // already overdue (targetDate < today). The effective selectable window
    // collapses to [firstDate, firstDate] in that degenerate case.
    _effectiveFirst = widget.firstDate;
    _effectiveLast = widget.lastDate.isBefore(widget.firstDate)
        ? widget.firstDate
        : widget.lastDate;
    // Clamp the initial due date into [firstDate, lastDate] so the displayed
    // value is selectable and showDatePicker's `!initialDate.isBefore(firstDate)`
    // assertion holds even when the task/phase is already in the past.
    _dueDate = _clampDate(widget.initialDueDate);
  }

  late final DateTime _effectiveFirst;
  late final DateTime _effectiveLast;

  DateTime _clampDate(DateTime d) {
    if (d.isBefore(_effectiveFirst)) return _effectiveFirst;
    if (d.isAfter(_effectiveLast)) return _effectiveLast;
    return d;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _clampDate(_dueDate),
      firstDate: _effectiveFirst,
      lastDate: _effectiveLast,
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    Navigator.pop(
      context,
      _TaskEditResult(
        title: title,
        note: _noteCtrl.text.trim(),
        dueDate: _dueDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialTitle.isEmpty ? '添加任务' : '编辑任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.event_outlined,
                color: AppColors.indigo,
              ),
              title: Text(
                '截止：${_dueDate.year}-${_dueDate.month.toString().padLeft(2, '0')}-${_dueDate.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: AppColors.inkFaint,
              ),
              onTap: _pickDate,
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 备赛详情页右上角「更多」自定义 bottom sheet（替换原生 PopupMenuButton）。
class _PlanMoreSheet extends StatelessWidget {
  const _PlanMoreSheet({required this.plan});

  final PreparationPlan plan;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.inkFaint.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            _MoreItem(
              icon: Icons.event_outlined,
              color: AppColors.indigo,
              title: '调整目标日期',
              onTap: () => Navigator.pop(context, 'targetDate'),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            _MoreItem(
              icon: Icons.archive_outlined,
              color: AppColors.inkSoft,
              title: '归档计划',
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            _MoreItem(
              icon: Icons.delete_outline,
              color: AppColors.danger,
              title: '删除计划',
              isLast: true,
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: AppColors.inkFaint),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }
}
