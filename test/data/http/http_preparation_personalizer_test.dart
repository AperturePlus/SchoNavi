import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/http/http_preparation_personalizer.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_personalizer.dart';

PreparationPersonalizationRequest _req() => PreparationPersonalizationRequest(
  competition: CompetitionSnapshot(
    id: 'comp_icpc',
    name: 'ACM-ICPC',
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
  timelineType: CompetitionTimelineType.submission,
  targetDate: DateTime(2026, 9, 1),
  eventEndDate: null,
  defenseDate: null,
  calendarToday: DateTime(2026, 6, 28),
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.beginner,
  phaseKeys: const [
    'team_formation',
    'topic_selection',
    'proposal_writing',
    'submission_polish',
    'defense_prep',
  ],
  profile: null,
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

ResponseBody _personalizationEnvelope() {
  return ResponseBody.fromString(
    jsonEncode({
      'code': 0,
      'message': 'ok',
      'data': {
        'phases': [
          {
            'key': 'proposal_writing',
            'optional_tasks': [
              {
                'template_key': 'fake_mock_train',
                'title': '模拟训练',
                'estimated_hours': 8,
              },
            ],
            'personalized_advice': '建议每周固定时段训练',
          },
        ],
        'global_advice': '保持节奏，关注官网通知',
      },
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('HTTP 调用后端返回个性化', () async {
    final p = HttpPreparationPersonalizer(
      _dio((_) async => _personalizationEnvelope()),
    );

    final r = await p.personalize(req: _req());

    expect(r, isA<Success<PreparationPersonalizationResult>>());
    final data = (r as Success<PreparationPersonalizationResult>).data;
    expect(data.phases, isNotEmpty);
    expect(data.phases.first.key, 'proposal_writing');
    expect(data.phases.first.optionalTasks.single.title, '模拟训练');
    expect(
      data.phases.first.optionalTasks.single.templateKey,
      'fake_mock_train',
    );
    expect(data.phases.first.optionalTasks.single.estimatedHours, 8);
    expect(data.phases.first.personalizedAdvice, '建议每周固定时段训练');
    expect(data.globalAdvice, '保持节奏，关注官网通知');
  });

  test('HTTP 端点经 guardApi：未知 phaseKey 仍被 DTO 校验丢弃', () async {
    final p = HttpPreparationPersonalizer(
      _dio((_) async => _personalizationEnvelope()),
    );

    // 请求里把 proposal_writing 从合法白名单中移除，后端返回的
    // proposal_writing 阶段应被 DTO 校验丢弃 → phases 为空但仍是 Success。
    final req = PreparationPersonalizationRequest(
      competition: _req().competition,
      timelineType: CompetitionTimelineType.submission,
      targetDate: _req().targetDate,
      eventEndDate: null,
      defenseDate: null,
      calendarToday: _req().calendarToday,
      weeklyCommitment: _req().weeklyCommitment,
      experienceLevel: _req().experienceLevel,
      phaseKeys: const ['team_formation'],
      profile: null,
    );

    final r = await p.personalize(req: req);

    expect(r, isA<Success<PreparationPersonalizationResult>>());
    expect(
      (r as Success<PreparationPersonalizationResult>).data.phases,
      isEmpty,
    );
  });
}
