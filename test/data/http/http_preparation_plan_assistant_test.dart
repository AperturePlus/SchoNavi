import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/http/http_preparation_plan_assistant.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_assistant.dart';

PreparationPlan _plan({String id = 'pp_1'}) => PreparationPlan(
  id: id,
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

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handler) {
  return Dio(BaseOptions(baseUrl: 'https://fake.local'))
    ..httpClientAdapter = _FakeAdapter(handler);
}

ResponseBody _assistantEnvelope({String requestId = 'req_test'}) {
  return ResponseBody.fromString(
    jsonEncode({
      'code': 0,
      'message': 'ok',
      'data': {
        'request_id': requestId,
        'reply': '我整理了两项可单独确认的调整。',
        'change_set': {
          'id': 'cs_fake_1',
          'base_plan_revision': 1,
          'cards': [
            {
              'id': 'cc_fake_move',
              'type': 'move_task',
              'target_task_id': 'task_core_algo',
              'new_date': '2026-05-22',
              'summary': '把【核心算法实现】移到 5 月 22 日',
              'rationale': '避开期末考试周，同时仍早于提交 DDL。',
              'status': 'pending',
            },
            {
              'id': 'cc_fake_add',
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
      },
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('HTTP 调用后端返回助手回复与改动卡', () async {
    final d = HttpPreparationPlanAssistant(
      _dio((_) async => _assistantEnvelope()),
    );

    final r = await d.suggestChanges(_req());

    expect(r, isA<Success<AssistantReply>>());
    final data = (r as Success<AssistantReply>).data;
    expect(data.reply, '我整理了两项可单独确认的调整。');
    expect(data.changeSet.id, 'cs_fake_1');
    expect(data.changeSet.cards.length, 2);
    final move = data.changeSet.cards[0];
    expect(move.type, ChangeCardType.moveTask);
    // fake 的 move_task new_date=2026-05-22 落在 [2026-05-01, 2026-05-30] 内。
    expect(move.status, ChangeCardStatus.pending);
    final add = data.changeSet.cards[1];
    expect(add.type, ChangeCardType.addTask);
    // add_task due_date=2026-06-05 落在 defense_prep [2026-05-31, 2026-06-10] 内。
    expect(add.status, ChangeCardStatus.pending);
  });

  test('后端返回 404 信封 → Failure', () async {
    final d = HttpPreparationPlanAssistant(
      _dio(
        (_) async => ResponseBody.fromString(
          jsonEncode({
            'code': 40401,
            'message': 'plan not found',
            'data': null,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    final r = await d.suggestChanges(_req());

    expect(r, isA<Failure<AssistantReply>>());
  });

  test('planId 与 planSnapshot.id 不一致触发构造断言', () {
    // spec §3.4：{id} 必须与 plan_snapshot.id 一致；构造时即失败。
    expect(
      () => PlanAssistantRequest(
        planId: 'pp_1',
        calendarToday: DateTime(2026, 5, 1),
        basePlanRevision: 1,
        planSnapshot: _plan(id: 'pp_other'),
        userMessage: 'hi',
        requestId: 'req_test',
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
