import '../entities/plan_change_card.dart';
import '../entities/preparation_plan.dart';
import '../../core/calendar_date.dart';

/// 任务只读快照：validator 仅读取，不修改计划。
class TaskSnapshot {
  const TaskSnapshot({
    required this.id,
    required this.kind,
    required this.dueDate,
    required this.completed,
  });

  final String id;
  final PreparationTaskKind kind;
  final DateTime dueDate;
  final bool completed;
}

/// 阶段只读快照。
class PhaseSnapshot {
  const PhaseSnapshot({
    required this.key,
    required this.startDate,
    required this.endDate,
    required this.tasks,
  });

  final String key;
  final DateTime startDate;
  final DateTime endDate;
  final List<TaskSnapshot> tasks;
}

/// 计划只读快照（spec §3.4 `plan_snapshot`）：validator 消费的最小只读视图。
/// 由 `PreparationPlan` 构造，但 validator 不依赖完整计划对象，便于测试与
/// 客户端与真实后端共用同一套校验。
class PlanSnapshot {
  const PlanSnapshot({
    required this.timelineType,
    required this.calendarToday,
    required this.targetDate,
    this.defenseDate,
    required this.phases,
  });

  final CompetitionTimelineType timelineType;
  final DateTime calendarToday;
  final DateTime targetDate;
  final DateTime? defenseDate;
  final List<PhaseSnapshot> phases;

  /// 从完整 [PreparationPlan] 构造只读快照。
  factory PlanSnapshot.fromPlan(
    PreparationPlan plan, {
    DateTime? calendarToday,
  }) {
    return PlanSnapshot(
      timelineType: plan.timelineType,
      calendarToday: calendarToday ?? CalendarDate.normalize(DateTime.now()),
      targetDate: CalendarDate.normalize(plan.targetDate),
      defenseDate: plan.defenseDate == null
          ? null
          : CalendarDate.normalize(plan.defenseDate!),
      phases: plan.phases
          .map(
            (p) => PhaseSnapshot(
              key: p.key,
              startDate: CalendarDate.normalize(p.startDate),
              endDate: CalendarDate.normalize(p.endDate),
              tasks: p.tasks
                  .map(
                    (t) => TaskSnapshot(
                      id: t.id,
                      kind: t.kind,
                      dueDate: CalendarDate.normalize(t.dueDate),
                      completed: t.completed,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList(),
    );
  }

  /// 按任务 id 查找任务及其所属阶段。
  ({PhaseSnapshot phase, TaskSnapshot task})? findTask(String taskId) {
    for (final phase in phases) {
      for (final task in phase.tasks) {
        if (task.id == taskId) return (phase: phase, task: task);
      }
    }
    return null;
  }

  /// 按阶段 key 查找阶段。
  PhaseSnapshot? findPhase(String key) {
    for (final phase in phases) {
      if (phase.key == key) return phase;
    }
    return null;
  }
}

/// 改动卡安全校验器（spec §3.5）。
///
/// 纯领域服务：无副作用，不读写计划。接收已解析的 [PlanChangeSet] 和
/// [PlanSnapshot]，返回带 `status` 标记的卡列表。后端已拒绝的卡保持原样；
/// 本地发现非法的卡为 `rejected` 并附带稳定 `rejectionCode` 与中文
/// `rejectionReason`。
///
/// 客户端在应用前执行同一规则；HTTP 后端为最终权威校验层。
class PlanChangeValidator {
  const PlanChangeValidator._();

  /// 校验 [changeSet] 中的所有卡。最多保留前 5 张（spec §3.5）。
  static List<PlanChangeCard> validate(
    PlanChangeSet changeSet,
    PlanSnapshot snapshot,
  ) {
    final limited = changeSet.cards.length > 5
        ? changeSet.cards.sublist(0, 5)
        : changeSet.cards;
    // spec: 超量部分丢弃并记录调试信息（此处仅丢弃，日志由调用方按需补充）。
    return limited
        .map((card) => _validateCard(card, snapshot))
        .toList(growable: false);
  }

  static PlanChangeCard _validateCard(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    if (card.status == ChangeCardStatus.rejected) {
      return card;
    }
    switch (card.type) {
      case ChangeCardType.moveTask:
        return _validateMoveTask(card, snapshot);
      case ChangeCardType.addTask:
        return _validateAddTask(card, snapshot);
      case ChangeCardType.deleteTask:
        return _validateDeleteTask(card, snapshot);
      case ChangeCardType.reschedulePhase:
        return _validateReschedulePhase(card, snapshot);
      case ChangeCardType.appendAdvice:
        return _validateAppendAdvice(card, snapshot);
    }
  }

  // --- moveTask -----------------------------------------------------------

  static PlanChangeCard _validateMoveTask(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    if (card.targetTaskId == null || card.newDate == null) {
      return _reject(
        card,
        'missing_required_fields',
        '缺少 targetTaskId 或 newDate',
      );
    }
    final found = snapshot.findTask(card.targetTaskId!);
    if (found == null) {
      return _reject(card, 'target_task_not_found', '目标任务不存在');
    }
    final task = found.task;
    if (task.completed) {
      return _reject(card, 'completed_task_protected', '已完成任务不可移动');
    }
    if (!_dateInRange(card.newDate!, found.phase, snapshot)) {
      return _reject(card, 'date_out_of_range', '新日期不在该阶段的合法区间内');
    }
    return card;
  }

  // --- addTask ------------------------------------------------------------

  static PlanChangeCard _validateAddTask(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    if (card.targetPhaseKey == null || card.newTask == null) {
      return _reject(
        card,
        'missing_required_fields',
        '缺少 targetPhaseKey 或 newTask',
      );
    }
    final phase = snapshot.findPhase(card.targetPhaseKey!);
    if (phase == null) {
      return _reject(card, 'target_phase_not_found', '目标阶段不存在');
    }
    final draft = card.newTask!;
    final title = draft.title.trim();
    if (title.isEmpty ||
        draft.estimatedHours < 1 ||
        draft.estimatedHours > 200) {
      return _reject(card, 'invalid_add_task_fields', '标题为空或工时不在 1–200 整数范围');
    }
    // 客户端强制 kind=userAdded；validator 只校验草稿字段（spec §3.5）。
    // dueDate 仍需落入该阶段所属区间。
    if (!_dateInRange(draft.dueDate, phase, snapshot)) {
      return _reject(card, 'date_out_of_range', '新任务 dueDate 不在阶段合法区间');
    }
    return card;
  }

  // --- deleteTask ---------------------------------------------------------

  static PlanChangeCard _validateDeleteTask(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    if (card.targetTaskId == null) {
      return _reject(card, 'missing_required_fields', '缺少 targetTaskId');
    }
    final found = snapshot.findTask(card.targetTaskId!);
    if (found == null) {
      return _reject(card, 'target_task_not_found', '目标任务不存在');
    }
    final task = found.task;
    if (task.completed) {
      return _reject(card, 'completed_task_protected', '已完成任务不可删除');
    }
    if (task.kind == PreparationTaskKind.required) {
      return _reject(card, 'required_task_delete_forbidden', '必做任务不可删除');
    }
    // optional / userAdded 允许删除。
    return card;
  }

  // --- reschedulePhase ----------------------------------------------------

  static PlanChangeCard _validateReschedulePhase(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    final schedule = card.phaseSchedule;
    if (schedule == null || schedule.isEmpty) {
      return _reject(card, 'missing_required_fields', '缺少 phaseSchedule');
    }
    // 1. 列出的 phaseKey 必须存在于快照。
    for (final draft in schedule) {
      if (snapshot.findPhase(draft.phaseKey) == null) {
        return _reject(
          card,
          'target_phase_not_found',
          '阶段 ${draft.phaseKey} 不存在',
        );
      }
    }
    // 2. 把草稿合并到完整阶段列表（未列出阶段保持原边界）。
    final merged = <String, PhaseScheduleDraft>{};
    final draftByKey = {for (final d in schedule) d.phaseKey: d};
    for (final phase in snapshot.phases) {
      final d = draftByKey[phase.key];
      merged[phase.key] = PhaseScheduleDraft(
        phaseKey: phase.key,
        startDate: d != null
            ? CalendarDate.normalize(d.startDate)
            : phase.startDate,
        endDate: d != null ? CalendarDate.normalize(d.endDate) : phase.endDate,
      );
    }
    // 3. 对完整阶段列表检查顺序、日期范围和重叠。
    final order = snapshot.phases.map((p) => p.key).toList();
    final reason = _checkPhaseOrderAndRange(order, merged, snapshot);
    if (reason != null) {
      return _reject(card, 'phase_schedule_invalid', reason);
    }
    return card;
  }

  /// 检查合并后的完整阶段列表：每个阶段 start<=end、落入合法区间、
  /// 相邻阶段不重叠且不反转。允许空档。
  static String? _checkPhaseOrderAndRange(
    List<String> order,
    Map<String, PhaseScheduleDraft> merged,
    PlanSnapshot snapshot,
  ) {
    DateTime? prevEnd;
    DateTime? prevStart;
    for (final key in order) {
      final d = merged[key]!;
      final start = CalendarDate.normalize(d.startDate);
      final end = CalendarDate.normalize(d.endDate);
      if (start.isAfter(end)) {
        return '阶段 $key 开始日晚于结束日';
      }
      // 合法区间：defense_prep 落在 [targetDate+1, defenseDate]；其余落在
      // [calendarToday, targetDate]（与任务日期范围规则一致）。
      if (key == 'defense_prep') {
        final defense = snapshot.defenseDate;
        if (defense == null) {
          return '无答辩日时 defense_prep 阶段非法';
        }
        final lo = snapshot.targetDate.add(const Duration(days: 1));
        if (start.isBefore(lo) || end.isAfter(defense)) {
          return 'defense_prep 阶段越界';
        }
      } else {
        final lo = snapshot.calendarToday;
        final hi = snapshot.targetDate;
        if (start.isBefore(lo) || end.isAfter(hi)) {
          return '阶段 $key 越出 [calendarToday, targetDate]';
        }
      }
      // 相邻阶段：不允许重叠或顺序反转，允许空档。
      // start <= prevEnd 视为重叠（含同日相接，因为日期为闭区间）；
      // start < prevStart 视为顺序反转。
      if (prevEnd != null && !start.isAfter(prevEnd)) {
        return '阶段 $key 与前一阶段重叠或相接';
      }
      if (prevStart != null && start.isBefore(prevStart)) {
        return '阶段 $key 开始日早于前一阶段（顺序反转）';
      }
      prevEnd = end;
      prevStart = start;
    }
    return null;
  }

  // --- appendAdvice -------------------------------------------------------

  static PlanChangeCard _validateAppendAdvice(
    PlanChangeCard card,
    PlanSnapshot snapshot,
  ) {
    final text = card.adviceText?.trim() ?? '';
    if (text.isEmpty) {
      return _reject(card, 'invalid_advice_fields', 'adviceText 为空');
    }
    if (card.targetPhaseKey != null &&
        snapshot.findPhase(card.targetPhaseKey!) == null) {
      return _reject(card, 'target_phase_not_found', '目标阶段不存在');
    }
    return card;
  }

  // --- 日期区间 ------------------------------------------------------------

  /// 判断 [date] 是否落在任务所属阶段 [phase] 的合法区间内（spec §3.5）。
  static bool _dateInRange(
    DateTime date,
    PhaseSnapshot phase,
    PlanSnapshot snapshot,
  ) {
    final d = CalendarDate.normalize(date);
    if (snapshot.timelineType == CompetitionTimelineType.eventWindow) {
      // 窗口型：所有可修改任务日期在 [calendarToday, targetDate]。
      return !d.isBefore(snapshot.calendarToday) &&
          !d.isAfter(snapshot.targetDate);
    }
    // 提交型：defense_prep 在 [targetDate+1, defenseDate]；其余在
    // [calendarToday, targetDate]；无 defenseDate 时 defense_prep 非法。
    if (phase.key == 'defense_prep') {
      final defense = snapshot.defenseDate;
      if (defense == null) return false;
      final lo = snapshot.targetDate.add(const Duration(days: 1));
      return !d.isBefore(lo) && !d.isAfter(defense);
    }
    return !d.isBefore(snapshot.calendarToday) &&
        !d.isAfter(snapshot.targetDate);
  }

  static PlanChangeCard _reject(
    PlanChangeCard card,
    String code,
    String reason,
  ) => card.copyWith(
    status: ChangeCardStatus.rejected,
    rejectionCode: code,
    rejectionReason: reason,
  );
}
