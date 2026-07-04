import '../../core/calendar_date.dart';

/// 改动卡类型（spec §2.6）。
enum ChangeCardType {
  moveTask,
  addTask,
  deleteTask,
  reschedulePhase,
  appendAdvice,
}

/// 改动卡状态（spec §2.6）。
enum ChangeCardStatus { pending, rejected, applied, declined, stale }

/// 新增任务草稿（spec §2.6）：AI 只产出字段，客户端生成 id 并强制
/// `kind=userAdded`。日期为日历日期（YYYY-MM-DD 往返）。
class NewTaskDraft {
  const NewTaskDraft({
    required this.title,
    required this.estimatedHours,
    required this.dueDate,
    this.note,
  });

  final String title;
  final int estimatedHours;
  final DateTime dueDate;
  final String? note;

  NewTaskDraft copyWith({
    String? title,
    int? estimatedHours,
    DateTime? dueDate,
    String? note,
  }) => NewTaskDraft(
    title: title ?? this.title,
    estimatedHours: estimatedHours ?? this.estimatedHours,
    dueDate: dueDate ?? this.dueDate,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'estimated_hours': estimatedHours,
    'due_date': CalendarDate.toIsoDay(dueDate),
    if (note != null) 'note': note,
  };

  factory NewTaskDraft.fromJson(Map<String, dynamic> json) => NewTaskDraft(
    title: json['title'] as String,
    estimatedHours: (json['estimated_hours'] as num).toInt(),
    dueDate: CalendarDate.parseIsoDay(json['due_date'] as String),
    note: json['note'] as String?,
  );

  @override
  String toString() =>
      'NewTaskDraft(title: $title, estimatedHours: $estimatedHours, '
      'dueDate: ${CalendarDate.toIsoDay(dueDate)}, note: $note)';
}

/// 阶段排期草稿（spec §2.6）：单张 reschedulePhase 卡列出本卡明确要重设
/// 边界的阶段；未列出的阶段保持原边界。
class PhaseScheduleDraft {
  const PhaseScheduleDraft({
    required this.phaseKey,
    required this.startDate,
    required this.endDate,
  });

  final String phaseKey;
  final DateTime startDate;
  final DateTime endDate;

  PhaseScheduleDraft copyWith({
    String? phaseKey,
    DateTime? startDate,
    DateTime? endDate,
  }) => PhaseScheduleDraft(
    phaseKey: phaseKey ?? this.phaseKey,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'phase_key': phaseKey,
    'start_date': CalendarDate.toIsoDay(startDate),
    'end_date': CalendarDate.toIsoDay(endDate),
  };

  factory PhaseScheduleDraft.fromJson(Map<String, dynamic> json) =>
      PhaseScheduleDraft(
        phaseKey: json['phase_key'] as String,
        startDate: CalendarDate.parseIsoDay(json['start_date'] as String),
        endDate: CalendarDate.parseIsoDay(json['end_date'] as String),
      );

  @override
  String toString() =>
      'PhaseScheduleDraft(phaseKey: $phaseKey, '
      'startDate: ${CalendarDate.toIsoDay(startDate)}, '
      'endDate: ${CalendarDate.toIsoDay(endDate)})';
}

/// 改动卡（spec §2.6）：AI/后端提议的单条计划变更。未给出 `status` 时默认为
/// `pending`；validator 校验后可能改为 `rejected` 并附带
/// `rejectionCode`/`rejectionReason`。
class PlanChangeCard {
  const PlanChangeCard({
    required this.id,
    required this.type,
    this.targetTaskId,
    this.targetPhaseKey,
    this.newDate,
    this.newTask,
    this.phaseSchedule,
    this.adviceText,
    required this.summary,
    required this.rationale,
    this.status = ChangeCardStatus.pending,
    this.rejectionCode,
    this.rejectionReason,
  });

  final String id;
  final ChangeCardType type;

  /// moveTask/deleteTask 目标任务 id。
  final String? targetTaskId;

  /// addTask/appendAdvice 目标阶段 key（appendAdvice 可空）。
  final String? targetPhaseKey;

  /// moveTask 新截止日；reschedulePhase 不使用此字段。
  final DateTime? newDate;

  /// addTask 新增任务草稿。
  final NewTaskDraft? newTask;

  /// reschedulePhase 本卡要重设边界的阶段列表。
  final List<PhaseScheduleDraft>? phaseSchedule;

  /// appendAdvice 建议正文。
  final String? adviceText;

  /// 展示用一句话描述（不参与定位任务或执行操作）。
  final String summary;

  /// 展示用理由（不参与定位任务或执行操作）。
  final String rationale;

  final ChangeCardStatus status;
  final String? rejectionCode;
  final String? rejectionReason;

  PlanChangeCard copyWith({
    String? id,
    ChangeCardType? type,
    String? targetTaskId,
    String? targetPhaseKey,
    DateTime? newDate,
    NewTaskDraft? newTask,
    List<PhaseScheduleDraft>? phaseSchedule,
    String? adviceText,
    String? summary,
    String? rationale,
    ChangeCardStatus? status,
    String? rejectionCode,
    String? rejectionReason,
  }) => PlanChangeCard(
    id: id ?? this.id,
    type: type ?? this.type,
    targetTaskId: targetTaskId ?? this.targetTaskId,
    targetPhaseKey: targetPhaseKey ?? this.targetPhaseKey,
    newDate: newDate ?? this.newDate,
    newTask: newTask ?? this.newTask,
    phaseSchedule: phaseSchedule ?? this.phaseSchedule,
    adviceText: adviceText ?? this.adviceText,
    summary: summary ?? this.summary,
    rationale: rationale ?? this.rationale,
    status: status ?? this.status,
    rejectionCode: rejectionCode,
    rejectionReason: rejectionReason,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': _encodeType(type),
    if (targetTaskId != null) 'target_task_id': targetTaskId,
    if (targetPhaseKey != null) 'target_phase_key': targetPhaseKey,
    if (newDate != null) 'new_date': CalendarDate.toIsoDay(newDate!),
    if (newTask != null) 'new_task': newTask!.toJson(),
    if (phaseSchedule != null)
      'phase_schedule': phaseSchedule!.map((p) => p.toJson()).toList(),
    if (adviceText != null) 'advice_text': adviceText,
    'summary': summary,
    'rationale': rationale,
    'status': _encodeStatus(status),
    if (rejectionCode != null) 'rejection_code': rejectionCode,
    if (rejectionReason != null) 'rejection_reason': rejectionReason,
  };

  factory PlanChangeCard.fromJson(Map<String, dynamic> json) => PlanChangeCard(
    id: json['id'] as String,
    type: _decodeType(json['type'] as String),
    targetTaskId: json['target_task_id'] as String?,
    targetPhaseKey: json['target_phase_key'] as String?,
    newDate: json['new_date'] == null
        ? null
        : CalendarDate.parseIsoDay(json['new_date'] as String),
    newTask: json['new_task'] == null
        ? null
        : NewTaskDraft.fromJson(json['new_task'] as Map<String, dynamic>),
    phaseSchedule: json['phase_schedule'] == null
        ? null
        : (json['phase_schedule'] as List<dynamic>)
              .map(
                (e) => PhaseScheduleDraft.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
    adviceText: json['advice_text'] as String?,
    summary: json['summary'] as String,
    rationale: json['rationale'] as String,
    status: _decodeStatus(json['status'] as String? ?? 'pending'),
    rejectionCode: json['rejection_code'] as String?,
    rejectionReason: json['rejection_reason'] as String?,
  );

  @override
  String toString() =>
      'PlanChangeCard(id: $id, type: $type, status: $status, '
      'rejectionCode: $rejectionCode)';
}

/// 一轮 AI 助手提议的改动卡集合（spec §2.6）。`basePlanRevision` 为生成
/// 时计划版本号；应用时若计划 revision 已变，剩余 pending 卡标为 stale。
class PlanChangeSet {
  const PlanChangeSet({
    required this.id,
    required this.basePlanRevision,
    required this.cards,
  });

  final String id;
  final int basePlanRevision;
  final List<PlanChangeCard> cards;

  PlanChangeSet copyWith({
    String? id,
    int? basePlanRevision,
    List<PlanChangeCard>? cards,
  }) => PlanChangeSet(
    id: id ?? this.id,
    basePlanRevision: basePlanRevision ?? this.basePlanRevision,
    cards: cards ?? this.cards,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'base_plan_revision': basePlanRevision,
    'cards': cards.map((c) => c.toJson()).toList(),
  };

  factory PlanChangeSet.fromJson(Map<String, dynamic> json) => PlanChangeSet(
    id: json['id'] as String,
    basePlanRevision: (json['base_plan_revision'] as num?)?.toInt() ?? 0,
    cards: (json['cards'] as List<dynamic>)
        .map((e) => PlanChangeCard.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// --- wire enum helpers ---------------------------------------------------

/// Dart enum `.name` 是 camelCase（如 `moveTask`），wire 值为 snake_case
/// （`move_task`）。这里集中处理双向映射，避免散落。
const Map<ChangeCardType, String> _changeCardTypeWire = {
  ChangeCardType.moveTask: 'move_task',
  ChangeCardType.addTask: 'add_task',
  ChangeCardType.deleteTask: 'delete_task',
  ChangeCardType.reschedulePhase: 'reschedule_phase',
  ChangeCardType.appendAdvice: 'append_advice',
};

const Map<String, ChangeCardType> _changeCardTypeWireReverse = {
  'move_task': ChangeCardType.moveTask,
  'add_task': ChangeCardType.addTask,
  'delete_task': ChangeCardType.deleteTask,
  'reschedule_phase': ChangeCardType.reschedulePhase,
  'append_advice': ChangeCardType.appendAdvice,
};

const Map<ChangeCardStatus, String> _changeCardStatusWire = {
  ChangeCardStatus.pending: 'pending',
  ChangeCardStatus.rejected: 'rejected',
  ChangeCardStatus.applied: 'applied',
  ChangeCardStatus.declined: 'declined',
  ChangeCardStatus.stale: 'stale',
};

const Map<String, ChangeCardStatus> _changeCardStatusWireReverse = {
  'pending': ChangeCardStatus.pending,
  'rejected': ChangeCardStatus.rejected,
  'applied': ChangeCardStatus.applied,
  'declined': ChangeCardStatus.declined,
  'stale': ChangeCardStatus.stale,
};

String _encodeType(ChangeCardType t) => _changeCardTypeWire[t] ?? t.name;

/// 公开解码：snake_case wire 值 → [ChangeCardType]，兼容 camelCase 兜底。
/// 未知值返回 null，由调用方决定抛错或丢弃。
ChangeCardType? decodeChangeCardType(String raw) =>
    _changeCardTypeWireReverse[raw] ??
    ChangeCardType.values.where((e) => e.name == raw).firstOrNull;

ChangeCardType _decodeType(String raw) =>
    decodeChangeCardType(raw) ?? ChangeCardType.appendAdvice;

String _encodeStatus(ChangeCardStatus s) => encodeChangeCardStatus(s);

/// 公开编码：[ChangeCardStatus] → snake_case wire 值。
String encodeChangeCardStatus(ChangeCardStatus status) =>
    _changeCardStatusWire[status] ?? status.name;

/// 公开解码：snake_case wire 值 → [ChangeCardStatus]，兼容 camelCase 兜底。
ChangeCardStatus? decodeChangeCardStatus(String raw) =>
    _changeCardStatusWireReverse[raw] ??
    ChangeCardStatus.values.where((e) => e.name == raw).firstOrNull;

ChangeCardStatus _decodeStatus(String raw) =>
    decodeChangeCardStatus(raw) ?? ChangeCardStatus.pending;
