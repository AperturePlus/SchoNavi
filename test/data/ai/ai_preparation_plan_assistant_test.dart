import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/ai/llm_client.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/ai/ai_preparation_plan_assistant.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';

class _StubLlm implements LlmClient {
  _StubLlm(this._out);

  final Result<String> _out;
  List<LlmMessage> lastMessages = const [];

  @override
  Future<Result<String>> complete({
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
  }) async {
    lastMessages = messages;
    return _out;
  }

  @override
  Stream<String> stream({
    required List<LlmMessage> messages,
    double temperature = 0.7,
  }) => throw UnimplementedError();
}

/// 按调用次数返回不同结果的 LLM stub：第 i 次（i 从 0 起）返回 `_outs[i]`。
/// 用于验证重试行为（畸形 → 合法的自愈）。
class _SequenceLlm implements LlmClient {
  _SequenceLlm(this._outs);
  final List<Result<String>> _outs;
  int callCount = 0;

  @override
  Future<Result<String>> complete({
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
  }) async {
    final i = callCount;
    callCount++;
    return _outs[i];
  }

  @override
  Stream<String> stream({
    required List<LlmMessage> messages,
    double temperature = 0.7,
  }) => throw UnimplementedError();
}

PreparationPlan _plan() => PreparationPlan(
  id: 'pp_1',
  competition: CompetitionSnapshot(
    id: 'comp_demo',
    name: 'Demo Cup',
    category: '计算机类',
    rulesSummary: CompetitionRulesSummary(
      signupTime: '',
      contestTime: '',
      teamSize: '',
      format: '',
      organizer: '',
      officialUrl: null,
    ),
  ),
  targetDate: DateTime(2026, 5, 30),
  timelineType: CompetitionTimelineType.submission,
  defenseDate: DateTime(2026, 6, 10),
  revision: 1,
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.intermediate,
  status: PreparationPlanStatus.active,
  phases: [
    PreparationPhase(
      key: 'proposal_writing',
      title: '方案撰写',
      startDate: DateTime(2026, 5, 10),
      endDate: DateTime(2026, 5, 22),
      tasks: [
        PreparationTask(
          id: 'task_core_algo',
          title: '核心算法实现',
          kind: PreparationTaskKind.required,
          estimatedHours: 16,
          dueDate: DateTime(2026, 5, 15),
        ),
      ],
    ),
    PreparationPhase(
      key: 'defense_prep',
      title: '答辩准备',
      startDate: DateTime(2026, 5, 31),
      endDate: DateTime(2026, 6, 10),
      tasks: const [],
    ),
  ],
  createdAt: DateTime(2026, 5, 1),
  updatedAt: DateTime(2026, 5, 1),
);

PlanAssistantRequest _req() => PlanAssistantRequest(
  planId: 'pp_1',
  calendarToday: DateTime(2026, 5, 1),
  basePlanRevision: 1,
  planSnapshot: _plan(),
  userMessage: '这周期末考没空，往后挪；答辩前留个模拟答辩',
  requestId: 'req_test',
);

Map<String, dynamic> _validReplyJson() => {
  'reply': '我整理了两项可单独确认的调整。',
  'change_set': {
    'id': 'cs_1',
    'base_plan_revision': 1,
    'cards': [
      {
        'id': 'cc_1',
        'type': 'move_task',
        'target_task_id': 'task_core_algo',
        'new_date': '2026-05-22',
        'summary': '把【核心算法实现】移到 5 月 22 日',
        'rationale': '避开期末考试周，同时仍早于提交 DDL。',
        'status': 'pending',
      },
      {
        'id': 'cc_2',
        'type': 'add_task',
        'target_phase_key': 'defense_prep',
        'new_task': {
          'title': '第二次模拟答辩',
          'estimated_hours': 3,
          'due_date': '2026-06-05',
          'note': '记录评委追问',
        },
        'summary': '答辩准备阶段新增一次模拟答辩',
        'rationale': '在正式答辩前预留复盘时间。',
        'status': 'pending',
      },
    ],
  },
};

void main() {
  test('解析合法 JSON 返回 reply 与 pending 卡（经 validator 通过）', () async {
    final llm = _StubLlm(Success(jsonEncode(_validReplyJson())));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Success<AssistantReply>>());
    final data = (r as Success<AssistantReply>).data;
    expect(data.reply, '我整理了两项可单独确认的调整。');
    expect(data.changeSet.id, 'cs_1');
    expect(data.changeSet.cards.length, 2);
    final move = data.changeSet.cards[0];
    expect(move.type, ChangeCardType.moveTask);
    expect(move.status, ChangeCardStatus.pending);
    expect(move.targetTaskId, 'task_core_algo');
    final add = data.changeSet.cards[1];
    expect(add.type, ChangeCardType.addTask);
    expect(add.status, ChangeCardStatus.pending);
    expect(add.newTask?.title, '第二次模拟答辩');
  });

  test('本地 LLM 最近历史包含 card_results', () async {
    final llm = _StubLlm(Success(jsonEncode(_validReplyJson())));
    final request = PlanAssistantRequest(
      planId: 'pp_1',
      calendarToday: DateTime(2026, 5, 1),
      basePlanRevision: 1,
      planSnapshot: _plan(),
      userMessage: '继续调整',
      requestId: 'req_test',
      history: const [
        AssistantHistoryEntry(
          role: 'assistant',
          content: '上一轮回复',
          cardResults: [
            AssistantCardResult(cardId: 'cc_1', status: 'applied'),
          ],
        ),
      ],
    );

    final r = await AiPreparationPlanAssistant(llm).suggestChanges(request);

    expect(r, isA<Success<AssistantReply>>());
    final userPrompt = llm.lastMessages.last.content;
    expect(userPrompt, contains('"card_results"'));
    expect(userPrompt, contains('"card_id":"cc_1"'));
    expect(userPrompt, contains('"status":"applied"'));
  });

  test('本地 LLM 系统提示词禁止 source refs 和 rejected 输出', () async {
    final llm = _StubLlm(Success(jsonEncode(_validReplyJson())));

    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());

    expect(r, isA<Success<AssistantReply>>());
    final systemPrompt = llm.lastMessages.first.content;
    expect(systemPrompt, contains('source_reference/source_refs'));
    expect(systemPrompt, contains('不要要求、生成或校验'));
    expect(systemPrompt, contains('plan_snapshot.phases[*].tasks[*].id'));
    expect(systemPrompt, contains('status 只能输出 pending'));
    expect(systemPrompt, contains('不要输出 rejected'));
  });

  test('越界卡被 validator 标 rejected，但 reply 仍为 Success', () async {
    final json = _validReplyJson();
    // move_task 新日期 2026-05-31 越出提交型非 defense_prep 合法区间
    // [calendarToday=2026-05-01, targetDate=2026-05-30]——validator 标
    // date_out_of_range。
    (json['change_set'] as Map)['cards'] = [
      {
        'id': 'cc_oob',
        'type': 'move_task',
        'target_task_id': 'task_core_algo',
        'new_date': '2026-05-31',
        'summary': '移到 DDL 后',
        'rationale': '尽量推迟。',
        'status': 'pending',
      },
    ];
    final llm = _StubLlm(Success(jsonEncode(json)));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Success<AssistantReply>>());
    final data = (r as Success<AssistantReply>).data;
    expect(data.changeSet.cards.length, 1);
    final card = data.changeSet.cards.first;
    expect(card.status, ChangeCardStatus.rejected);
    expect(card.rejectionCode, 'date_out_of_range');
  });

  test('畸形 JSON 返回 Failure', () async {
    final llm = _StubLlm(const Success('not json'));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Failure<AssistantReply>>());
    expect((r as Failure).error, isA<ServerException>());
  });

  test('Llm 未配置返回 Failure', () async {
    final llm = _StubLlm(const Failure(MissingLlmConfigurationException()));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Failure<AssistantReply>>());
    expect((r as Failure).error, isA<MissingLlmConfigurationException>());
  });

  test('change_set 缺失返回 Failure', () async {
    final llm = _StubLlm(Success(jsonEncode({'reply': '你好'})));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Failure<AssistantReply>>());
    expect((r as Failure).error, isA<ServerException>());
  });

  test('```json 代码块包裹的 JSON 仍可解析（清洗）', () async {
    final wrapped = '```json\n${jsonEncode(_validReplyJson())}\n```';
    final llm = _StubLlm(Success(wrapped));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Success<AssistantReply>>());
    final data = (r as Success<AssistantReply>).data;
    expect(data.changeSet.id, 'cs_1');
    expect(data.changeSet.cards.length, 2);
  });

  test('thinking 前缀 + 尾部多余文本仍可解析（取首 { 到末 }）', () async {
    final noisy =
        '好的，我来调整。\n{"reply":"已调整","change_set":${jsonEncode(_validReplyJson()['change_set'])}}\n以上是建议。';
    final llm = _StubLlm(Success(noisy));
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Success<AssistantReply>>());
    final data = (r as Success<AssistantReply>).data;
    expect(data.reply, '已调整');
    expect(data.changeSet.cards.length, 2);
  });

  test('首次畸形 + 第二次合法 → 重试后 Success', () async {
    final llm = _SequenceLlm([
      const Success('not json at all'),
      Success(jsonEncode(_validReplyJson())),
    ]);
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Success<AssistantReply>>());
    expect(llm.callCount, 2);
  });

  test('MissingLlm 错误直接 Failure，不重试（调用次数==1）', () async {
    final llm = _SequenceLlm([
      const Failure(MissingLlmConfigurationException()),
      const Failure(MissingLlmConfigurationException()),
      const Failure(MissingLlmConfigurationException()),
    ]);
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Failure<AssistantReply>>());
    expect((r as Failure).error, isA<MissingLlmConfigurationException>());
    expect(llm.callCount, 1);
  });

  test('连续 3 次畸形 JSON → Failure(ServerException)，调用次数==3', () async {
    final llm = _SequenceLlm([
      const Success('not json'),
      const Success('also not json'),
      const Success('{ broken'),
    ]);
    final r = await AiPreparationPlanAssistant(llm).suggestChanges(_req());
    expect(r, isA<Failure<AssistantReply>>());
    expect((r as Failure).error, isA<ServerException>());
    expect(llm.callCount, 3);
  });
}
