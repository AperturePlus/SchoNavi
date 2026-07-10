import '../../core/result/result.dart';
import '../entities/plan_change_card.dart';
import '../entities/preparation_plan.dart';

/// 助手历史单轮记录（spec §3.4 `history` 元素）：role、content 与上轮卡片结果。
/// 用于让 AI/HTTP 后端理解上下文，本身不参与校验。
class AssistantHistoryEntry {
  const AssistantHistoryEntry({
    required this.role,
    required this.content,
    this.cardResults = const <AssistantCardResult>[],
  });

  final String role;
  final String content;
  final List<AssistantCardResult> cardResults;
}

/// 上轮卡处理结果（spec §3.4 `history[].card_results`）。
class AssistantCardResult {
  const AssistantCardResult({required this.cardId, required this.status});

  final String cardId;
  final String status;
}

/// 后端助手请求（spec §3.4）：携带日历基准、计划版本、计划快照、用户消息和
/// 最近历史。供 HTTP [PreparationPlanAssistant] 实现消费。
class PlanAssistantRequest {
  PlanAssistantRequest({
    required this.planId,
    required this.calendarToday,
    required this.basePlanRevision,
    required this.planSnapshot,
    required this.userMessage,
    required this.requestId,
    this.history = const <AssistantHistoryEntry>[],
  }) : assert(
         planId == planSnapshot.id,
         'planId ($planId) 必须与 planSnapshot.id (${planSnapshot.id}) 一致',
       );

  /// 计划 id，用于 HTTP 路径 `/:id/assistant`；应与 planSnapshot.id 一致。
  final String planId;

  /// 日历基准（YYYY-MM-DD 往返）。
  final DateTime calendarToday;

  /// 生成时计划的 revision。
  final int basePlanRevision;

  /// 完整计划快照（服务端推理与校验的唯一事实来源）。
  final PreparationPlan planSnapshot;

  /// 用户本轮自然语言消息。
  final String userMessage;

  /// 最近历史（最多若干轮，由调用方截断）。
  final List<AssistantHistoryEntry> history;

  /// 客户端生成的请求标识，服务端 echo 回来，用于跨抽屉关闭追踪该轮。
  final String requestId;
}

/// 后端助手回复（spec §3.4 response）：自然语言 `reply` + 已过共享 validator 的
/// [PlanChangeSet]。validator 可能将部分卡标为 `rejected`，调用方仍按 Success
/// 处理（reply 本身有效）；JSON 解析失败才返回 Failure。
class AssistantReply {
  const AssistantReply({
    required this.reply,
    required this.changeSet,
    this.requestId = '',
  });

  final String reply;
  final PlanChangeSet changeSet;

  /// 服务端 echo 的请求标识（缺失时为空串，兼容旧 fake）。
  final String requestId;
}

/// 备赛日历助手：根据计划快照、用户消息和最近历史，输出自然语言回复与
/// 最多 5 张结构化改动卡（经共享 `PlanChangeValidator` 校验）。

abstract interface class PreparationPlanAssistant {
  Future<Result<AssistantReply>> suggestChanges(PlanAssistantRequest request);
}
