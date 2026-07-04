import '../../core/calendar_date.dart';
import '../../domain/entities/plan_change_card.dart';

/// DTO：从 AI 助手 LLM/HTTP 返回的 JSON `data` 解码为 [PlanChangeSet]。
///
/// 原始结构（spec §3.4 response data）：
/// ```json
/// {
///   "reply": "...",
///   "change_set": {
///     "id": "cs_1",
///     "base_plan_revision": 3,
///     "cards": [ { "id": "cc_1", "type": "move_task", ... } ]
///   }
/// }
/// ```
/// 卡 `status` 从 wire 读取，缺省或未知值降级为 `pending`；后续由共享
/// [PlanChangeValidator] 作为二次防线标记非法卡。解码失败（结构非对象、type 非法、
/// 日期格式错误等）抛 [FormatException]，由调用方兜底转
/// `Failure(ServerException)`，不得写计划（spec §3.5 末条）。
class PlanChangeSetDto {
  PlanChangeSetDto({required this.reply, required this.changeSet});

  /// AI 自然语言回复正文。
  final String reply;

  /// 解码后的改动卡集合（卡状态来自 wire，缺省或未知值为 `pending`）。
  final PlanChangeSet changeSet;

  /// 从 JSON `data` 解码。
  ///
  /// `reply` 缺失时按空串处理；`change_set` 缺失或非对象时抛
  /// [FormatException]。
  factory PlanChangeSetDto.fromJson(Map<String, dynamic> json) {
    final reply = (json['reply']?.toString() ?? '').trim();

    final rawSet = json['change_set'] ?? json['changeSet'];
    if (rawSet is! Map) {
      throw const FormatException('change_set missing or not an object');
    }
    final setJson = Map<String, dynamic>.from(rawSet);

    final rawId = setJson['id']?.toString();
    if (rawId == null || rawId.isEmpty) {
      throw const FormatException('change_set.id missing');
    }
    final baseRevision =
        (setJson['base_plan_revision'] as num?)?.toInt() ??
        (setJson['basePlanRevision'] as num?)?.toInt() ??
        0;

    final rawCards = setJson['cards'];
    if (rawCards is! List) {
      throw const FormatException('change_set.cards missing or not a list');
    }

    final cards = <PlanChangeCard>[];
    for (final item in rawCards) {
      if (item is! Map) {
        throw const FormatException('change_set.cards[*] not an object');
      }
      cards.add(_decodeCard(Map<String, dynamic>.from(item)));
    }

    return PlanChangeSetDto(
      reply: reply,
      changeSet: PlanChangeSet(
        id: rawId,
        basePlanRevision: baseRevision,
        cards: cards,
      ),
    );
  }

  PlanChangeSetDto copyWith({String? reply, PlanChangeSet? changeSet}) =>
      PlanChangeSetDto(
        reply: reply ?? this.reply,
        changeSet: changeSet ?? this.changeSet,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'reply': reply,
    'change_set': changeSet.toJson(),
  };
}

PlanChangeCard _decodeCard(Map<String, dynamic> json) {
  final id = json['id']?.toString();
  if (id == null || id.isEmpty) {
    throw const FormatException('card.id missing');
  }
  final type = _decodeType(json['type']?.toString());
  final summary = (json['summary']?.toString() ?? '').trim();
  final rationale = (json['rationale']?.toString() ?? '').trim();
  final status =
      decodeChangeCardStatus(json['status']?.toString() ?? '') ??
      ChangeCardStatus.pending;

  return PlanChangeCard(
    id: id,
    type: type,
    targetTaskId: _optionalString(
      json['target_task_id'] ?? json['targetTaskId'],
    ),
    targetPhaseKey: _optionalString(
      json['target_phase_key'] ?? json['targetPhaseKey'],
    ),
    newDate: _decodeDay(json['new_date'] ?? json['newDate']),
    newTask: _decodeNewTask(json['new_task'] ?? json['newTask']),
    phaseSchedule: _decodePhaseSchedule(
      json['phase_schedule'] ?? json['phaseSchedule'],
    ),
    adviceText: _optionalString(json['advice_text'] ?? json['adviceText']),
    summary: summary,
    rationale: rationale,
    status: status,
    rejectionCode: _optionalString(
      json['rejection_code'] ?? json['rejectionCode'],
    ),
    rejectionReason: _optionalString(
      json['rejection_reason'] ?? json['rejectionReason'],
    ),
  );
}

NewTaskDraft? _decodeNewTask(Object? raw) {
  if (raw is! Map) return null;
  final json = Map<String, dynamic>.from(raw);
  final title = _optionalString(json['title']);
  if (title == null) {
    throw const FormatException('new_task.title missing');
  }
  final hours = json['estimated_hours'] ?? json['estimatedHours'];
  if (hours is! num) {
    throw const FormatException(
      'new_task.estimated_hours missing or not a number',
    );
  }
  // spec §3.5：estimatedHours 1–200 整数。非整数（如 4.5）拒绝，
  // 不得静默截断（否则 4.7 被截为 4 后仍落入合法区间而通过校验）。
  if (hours != hours.roundToDouble()) {
    throw const FormatException('new_task.estimated_hours must be an integer');
  }
  final due = _decodeDay(json['due_date'] ?? json['dueDate']);
  if (due == null) {
    throw const FormatException('new_task.due_date missing');
  }
  return NewTaskDraft(
    title: title,
    estimatedHours: hours.toInt(),
    dueDate: due,
    note: _optionalString(json['note']),
  );
}

List<PhaseScheduleDraft>? _decodePhaseSchedule(Object? raw) {
  if (raw is! List) return null;
  final out = <PhaseScheduleDraft>[];
  for (final item in raw) {
    if (item is! Map) {
      throw const FormatException('phase_schedule[*] not an object');
    }
    final json = Map<String, dynamic>.from(item);
    final key = _optionalString(json['phase_key'] ?? json['phaseKey']);
    if (key == null) {
      throw const FormatException('phase_schedule[*].phase_key missing');
    }
    final start = _decodeDay(json['start_date'] ?? json['startDate']);
    final end = _decodeDay(json['end_date'] ?? json['endDate']);
    if (start == null || end == null) {
      throw const FormatException(
        'phase_schedule[*].start_date/end_date missing',
      );
    }
    out.add(PhaseScheduleDraft(phaseKey: key, startDate: start, endDate: end));
  }
  return out;
}

DateTime? _decodeDay(Object? raw) {
  if (raw == null) return null;
  return CalendarDate.parseIsoDay(raw.toString());
}

ChangeCardType _decodeType(String? raw) {
  if (raw == null || raw.isEmpty) {
    throw const FormatException('card.type missing');
  }
  final decoded = decodeChangeCardType(raw);
  if (decoded == null) {
    throw FormatException('unknown card type: $raw');
  }
  return decoded;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}
