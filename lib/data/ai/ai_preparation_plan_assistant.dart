import 'dart:convert';

import '../../core/ai/llm_client.dart';
import '../../core/calendar_date.dart';
import '../../core/error/app_exception.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/preparation_plan_assistant.dart';
import '../../domain/services/plan_change_validator.dart';
import '../dto/plan_assistant_dtos.dart';

export '../../domain/repositories/preparation_plan_assistant.dart'
    show
        PlanAssistantRequest,
        AssistantReply,
        AssistantHistoryEntry,
        AssistantCardResult;

/// 本地 LLM 实现：构造 spec §5.3 提示词约束 AI 仅输出已知卡类型与快照中存在的
/// task_id/phase_key，输出纯 JSON；解析时先用 `PlanChangeSetDto.fromJson`
/// 解码，再用请求 `plan_snapshot` 构造 `PlanSnapshot` 并经共享
/// `PlanChangeValidator` 标记越界/非法卡为 `rejected`。
class AiPreparationPlanAssistant implements PreparationPlanAssistant {
  AiPreparationPlanAssistant(this._llm);

  final LlmClient _llm;

  /// LLM 调用重试上限。仅对「调用成功但 JSON 畸形」重试；`MissingLlm`/
  /// 网络等 `complete` 本身 Failure 的错误不重试，避免无 key 时空转。
  static const int _maxAttempts = 3;

  @override
  Future<Result<AssistantReply>> suggestChanges(
    PlanAssistantRequest request,
  ) async {
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final result = await _llm.complete(
        messages: [
          const LlmMessage('system', _systemPrompt),
          LlmMessage('user', _buildUserMessage(request)),
        ],
        jsonMode: true,
        temperature: 0.3,
      );

      // complete 本身失败（未配置/网络/超时）：不重试，直接返回。
      if (result is Failure<String>) return Failure(result.error);

      final content = (result as Success<String>).data;
      final decoded = _decodeOnce(request, content);
      if (decoded is Success<AssistantReply>) return decoded;
      // JSON 畸形：若仍有重试次数，继续重试（靠 LLM 输出随机性自愈）。
    }
    return const Failure(ServerException());
  }

  /// 单次解码：JSON 清洗 → 解析 → validator 校验。任意步骤失败返回
  /// `Failure(ServerException)`，由调用方决定是否重试。
  Result<AssistantReply> _decodeOnce(
    PlanAssistantRequest request,
    String content,
  ) {
    try {
      final decoded = jsonDecode(_extractJson(content));
      if (decoded is! Map<String, dynamic>) {
        return const Failure(ServerException());
      }
      final snapshot = PlanSnapshot.fromPlan(
        request.planSnapshot,
        calendarToday: request.calendarToday,
      );
      final dto = AssistantReplyDto.fromJson(decoded, snapshot);
      return Success(dto.toEntity());
    } catch (_) {
      return const Failure(ServerException());
    }
  }

  /// 从 LLM 输出中提取 JSON 文本。DeepSeek `deepseek-v4-flash` 默认 thinking
  /// 模式，即使 `jsonMode=true` 也可能返回 ```json 代码块包裹、thinking 前缀
  /// 或首尾多余文本。先剥代码块，再取首个 `{` 到末个 `}` 的子串。
  static String _extractJson(String content) {
    var text = content.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final fenceMatch = fence.firstMatch(text);
    if (fenceMatch != null) {
      text = fenceMatch.group(1)!.trim();
    }
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1);
    }
    return text.trim();
  }

  String _buildUserMessage(PlanAssistantRequest req) {
    final snapshotJson = jsonEncode(req.planSnapshot.toJson());
    final historyJson = req.history.map((h) {
      return <String, dynamic>{
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
      };
    }).toList();
    final historySection = req.history.isEmpty
        ? ''
        : '\n【最近历史】${jsonEncode(historyJson)}';
    return '【日历基准】${CalendarDate.toIsoDay(req.calendarToday)}\n'
        '【计划版本】${req.basePlanRevision}\n'
        '【计划快照】$snapshotJson\n'
        '【用户消息】${req.userMessage}$historySection\n'
        '请根据计划快照、用户消息和最近历史，输出自然语言回复和最多 5 张改动卡。';
  }

  static const String _systemPrompt = '''
你是 SchoNavi 的备赛日历助手。根据计划快照、用户消息和最近历史，
输出自然语言回复和最多 5 张结构化改动卡。

规则：
1. 类型仅限 move_task|add_task|delete_task|reschedule_phase|append_advice。
2. 只能引用快照中存在的 task_id 和 phase_key。
3. 必做任务、已完成任务不可删除；已完成任务不可移动。
4. 新增任务只输出 NewTaskDraft，不输出 id 或 kind。
5. 日期必须符合时间类型和阶段的合法区间。
6. reschedule_phase 必须给出受影响阶段的完整 phase_schedule。
7. 不确定如何安全修改时使用 append_advice，或返回空 cards，不要猜测。
8. summary 描述改什么，rationale 解释为什么。
9. 仅输出 JSON，不输出 Markdown 代码块。
''';
}
