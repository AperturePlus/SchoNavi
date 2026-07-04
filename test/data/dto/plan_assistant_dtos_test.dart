import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/calendar_date.dart';
import 'package:scho_navi/data/dto/plan_assistant_dtos.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_assistant.dart';
import 'package:scho_navi/domain/services/plan_change_validator.dart';

PreparationPlan _plan() => PreparationPlan(
  id: 'pp_1',
  competition: CompetitionSnapshot(
    id: 'comp_demo',
    name: 'Demo',
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
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.intermediate,
  status: PreparationPlanStatus.active,
  phases: const [],
  createdAt: DateTime(2026, 5, 1),
  updatedAt: DateTime(2026, 5, 1),
);

void main() {
  test('planAssistantRequestToJson 输出 request_id', () {
    final req = PlanAssistantRequest(
      planId: 'pp_1',
      calendarToday: CalendarDate.normalize(DateTime(2026, 5, 1)),
      basePlanRevision: 1,
      planSnapshot: _plan(),
      userMessage: '问',
      requestId: 'req_xyz',
    );
    final json = planAssistantRequestToJson(req);
    expect(json['request_id'], 'req_xyz');
  });

  test('planAssistantRequestToJson 输出 history card_results', () {
    final req = PlanAssistantRequest(
      planId: 'pp_1',
      calendarToday: CalendarDate.normalize(DateTime(2026, 5, 1)),
      basePlanRevision: 1,
      planSnapshot: _plan(),
      userMessage: '问',
      requestId: 'req_xyz',
      history: const [
        AssistantHistoryEntry(
          role: 'assistant',
          content: '上一轮回复',
          cardResults: [
            AssistantCardResult(cardId: 'card-1', status: 'applied'),
          ],
        ),
      ],
    );
    final json = planAssistantRequestToJson(req);
    final history = json['history'] as List<dynamic>;
    expect(history, hasLength(1));
    expect(history.first, {
      'role': 'assistant',
      'content': '上一轮回复',
      'card_results': [
        {'card_id': 'card-1', 'status': 'applied'},
      ],
    });
  });

  test('AssistantReplyDto.fromJson 解析 request_id 并带入 entity', () {
    final data = <String, dynamic>{
      'reply': '已调整',
      'request_id': 'req_xyz',
      'change_set': {
        'id': 'cs_1',
        'base_plan_revision': 1,
        'cards': <dynamic>[],
      },
    };
    final snapshot = PlanSnapshot.fromPlan(
      _plan(),
      calendarToday: DateTime(2026, 5, 1),
    );
    final dto = AssistantReplyDto.fromJson(data, snapshot);
    expect(dto.toEntity().requestId, 'req_xyz');
  });

  test('AssistantReplyDto.fromJson 保留服务端 rejected 原因', () {
    final data = <String, dynamic>{
      'reply': '已调整',
      'change_set': {
        'id': 'cs_1',
        'base_plan_revision': 1,
        'cards': [
          {
            'id': 'cc_1',
            'type': 'append_advice',
            'target_phase_key': 'missing',
            'advice_text': '建议',
            'summary': '追加建议',
            'rationale': '阶段不存在',
            'status': 'rejected',
            'rejection_code': 'invalid_target',
            'rejection_reason': '目标阶段不存在',
          },
        ],
      },
    };
    final snapshot = PlanSnapshot.fromPlan(
      _plan(),
      calendarToday: DateTime(2026, 5, 1),
    );
    final dto = AssistantReplyDto.fromJson(data, snapshot);
    final card = dto.toEntity().changeSet.cards.first;
    expect(card.status, ChangeCardStatus.rejected);
    expect(card.rejectionCode, 'invalid_target');
    expect(card.rejectionReason, '目标阶段不存在');
  });

  test('AssistantReplyDto 旧响应缺 request_id 降级空串', () {
    final data = <String, dynamic>{
      'reply': '已调整',
      'change_set': {
        'id': 'cs_1',
        'base_plan_revision': 1,
        'cards': <dynamic>[],
      },
    };
    final snapshot = PlanSnapshot.fromPlan(
      _plan(),
      calendarToday: DateTime(2026, 5, 1),
    );
    final dto = AssistantReplyDto.fromJson(data, snapshot);
    expect(dto.toEntity().requestId, '');
  });
}
