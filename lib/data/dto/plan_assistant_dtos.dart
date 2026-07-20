import '../../core/calendar_date.dart';
import '../../domain/entities/plan_change_card.dart';
import '../../domain/repositories/preparation_plan_assistant.dart';
import '../../domain/services/plan_change_validator.dart';
import 'plan_change_card_dtos.dart';

/// 序列化 [PlanAssistantRequest] 为 HTTP 请求体（spec §3.4 结构）。
///
/// `calendar_today` 为 YYYY-MM-DD；`plan_snapshot` 为完整计划 JSON；
/// `history` 仅含 role/content 与上轮卡片结果，本身不参与校验。
Map<String, dynamic> planAssistantRequestToJson(PlanAssistantRequest req) {
  return <String, dynamic>{
    'calendar_today': CalendarDate.toIsoDay(req.calendarToday),
    'base_plan_revision': req.basePlanRevision,
    'plan_snapshot': req.planSnapshot.toJson(),
    'user_message': req.userMessage,
    'request_id': req.requestId,
    if (req.history.isNotEmpty)
      'history': req.history
          .map(
            (h) => <String, dynamic>{
              'role': h.role,
              'content': h.content,
              if (h.cardResults.isNotEmpty)
                'card_results': h.cardResults
                    .map(
                      (c) => <String, dynamic>{
                        'card_id': c.cardId,
                        'status': c.status,
                      },
                    )
                    .toList(),
            },
          )
          .toList(),
  };
}

/// DTO：从 后端助手返回的 JSON `data` 解码为 [AssistantReply]。
///
/// 共享 validator 集成点：先用 [PlanChangeSetDto.fromJson] 把原始 `change_set`
/// 解码成 [PlanChangeSet]，再用请求 `plan_snapshot` 构造 [PlanSnapshot] 并经
/// [PlanChangeValidator.validate] 标记越界/非法卡为 `rejected`。AI 与 HTTP
/// 路径共用此解码+校验，DRY。
///
/// 解码失败（结构非对象、type 非法、日期格式错误等）抛 [FormatException]，
/// 由调用方兜底转 `Failure(ServerException)`，不得写计划（spec §3.5 末条）。
class AssistantReplyDto {
  AssistantReplyDto({
    required this.reply,
    required this.changeSet,
    this.requestId = '',
  });

  final String reply;
  final PlanChangeSet changeSet;

  /// 服务端 echo 的请求标识（缺失时为空串，兼容旧 fake）。
  final String requestId;

  /// 从 JSON `data` 解码并跑共享 validator。
  ///
  /// [planSnapshot] 为请求携带的计划快照，validator 据此标记 rejected 卡。
  /// 注意：validator 最多保留前 5 张卡（spec §3.5），此处沿用其截断结果。
  /// `request_id` 缺失时降级为空串，兼容旧 fake/HTTP 响应。
  factory AssistantReplyDto.fromJson(
    Map<String, dynamic> json,
    PlanSnapshot planSnapshot,
  ) {
    final raw = PlanChangeSetDto.fromJson(json);
    final validated = PlanChangeValidator.validate(raw.changeSet, planSnapshot);
    return AssistantReplyDto(
      reply: raw.reply,
      changeSet: raw.changeSet.copyWith(cards: validated),
      requestId: (json['request_id']?.toString()) ?? '',
    );
  }

  AssistantReply toEntity() =>
      AssistantReply(reply: reply, changeSet: changeSet, requestId: requestId);
}
