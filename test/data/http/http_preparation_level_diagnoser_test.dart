import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/http/http_preparation_level_diagnoser.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_level_diagnoser.dart';

LevelDiagnosisRequest _req() => LevelDiagnosisRequest(
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
  answers: const [
    DiagnosisAnswer(questionKey: 'prior_experience', answer: '拿过校级以上奖'),
    DiagnosisAnswer(questionKey: 'domain_familiarity', answer: '熟悉'),
  ],
  profile: null,
);

ResponseBody _diagnoseEnvelope() {
  return ResponseBody.fromString(
    jsonEncode({
      'code': 0,
      'message': 'ok',
      'data': {
        'level': 'intermediate',
        'rationale': '根据你的参赛经历和领域熟悉度，你已具备进阶基础。',
        'suggestion': '建议按进阶档排期；时间充裕时可增加老手档训练。',
      },
    }),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

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

void main() {
  test('HTTP 调用后端返回水平诊断', () async {
    final d = HttpPreparationLevelDiagnoser(
      _dio((_) async => _diagnoseEnvelope()),
    );

    final r = await d.diagnose(_req());

    expect(r, isA<Success<LevelDiagnosisSuggestion>>());
    final data = (r as Success<LevelDiagnosisSuggestion>).data;
    expect(data.level, ExperienceLevel.intermediate);
    expect(data.rationale, '根据你的参赛经历和领域熟悉度，你已具备进阶基础。');
    expect(data.suggestion, '建议按进阶档排期；时间充裕时可增加老手档训练。');
  });

  test('未注册端点返回 404 信封 → Failure', () async {
    final d = HttpPreparationLevelDiagnoser(
      _dio(
        (_) async => ResponseBody.fromString(
          jsonEncode({
            'code': 40401,
            'message': 'fake backend: route not registered',
            'data': null,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      ),
    );

    final r = await d.diagnose(_req());

    expect(r, isA<Failure<LevelDiagnosisSuggestion>>());
  });
}
