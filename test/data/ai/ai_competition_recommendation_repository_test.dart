import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/ai/llm_client.dart';
import 'package:scho_navi/core/ai/missing_llm_client.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/ai/ai_competition_recommendation_repository.dart';
import 'package:scho_navi/data/fixtures/competition_catalog.dart';
import 'package:scho_navi/domain/entities/competition.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';

class _FakeLlm implements LlmClient {
  _FakeLlm(this._result);

  final Result<String> _result;
  bool? lastJsonMode;
  String? lastUserContent;

  @override
  Future<Result<String>> complete({
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
  }) async {
    lastJsonMode = jsonMode;
    lastUserContent = messages.last.content;
    return _result;
  }

  @override
  Stream<String> stream({
    required List<LlmMessage> messages,
    double temperature = 0.7,
  }) => throw UnimplementedError();
}

class _FixedCompetitionSource implements CompetitionCandidateSource {
  const _FixedCompetitionSource(this.pool);

  final List<RecommendedCompetition> pool;

  @override
  List<RecommendedCompetition> candidatesFor(String prompt) => pool;
}

const _math = RecommendedCompetition(
  id: 'comp_math_modeling',
  name: '全国大学生数学建模竞赛',
  category: '理学类',
  level: '国家级',
  tags: ['数学建模', '团队赛'],
  teamSize: '3 人团队',
  signupTime: '以官网通知为准',
  contestTime: '通常每年 9 月',
  format: '建模、编程和论文写作',
  organizer: '中国工业与应用数学学会',
  officialUrl: 'http://www.mcm.edu.cn/',
  reason: '',
  preparationTips: ['训练论文写作'],
  limitations: ['以官网通知为准。'],
  matchScore: 0,
);

void main() {
  const source = _FixedCompetitionSource([_math]);

  test('parses result and fills competition facts from candidates', () async {
    final content = jsonEncode({
      'understanding': {
        'directions': ['数学建模'],
        'categories': ['理学类'],
        'timingPreferences': ['秋季/下半年'],
        'teamPreferences': ['团队赛'],
        'uncertainties': <String>[],
      },
      'recommendations': [
        {
          'competitionId': 'comp_math_modeling',
          'reason': '你的需求偏建模和数据分析，适合参加数模。',
          'preparationTips': ['训练建模论文结构'],
          'limitations': ['以官网通知为准'],
          'matchScore': 1.2,
        },
      ],
      'followUpQuestions': ['是否已有队友？'],
    });
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(Success(content)),
      candidates: source,
    );

    final result = await repo.getRecommendations(prompt: '数学建模团队赛');

    final data = (result as Success).data;
    expect(data.understanding.directions, ['数学建模']);
    expect(data.followUpQuestions, ['是否已有队友？']);
    final rec = data.recommendations.single;
    expect(rec.id, 'comp_math_modeling');
    expect(rec.name, '全国大学生数学建模竞赛');
    expect(rec.category, '理学类');
    expect(rec.reason, contains('数模'));
    expect(rec.preparationTips, ['训练建模论文结构']);
    expect(rec.limitations, ['以官网通知为准']);
    expect(rec.matchScore, 1);
  });

  test('normalizes technical understanding tokens from LLM output', () async {
    final content = jsonEncode({
      'understanding': {
        'directions': ['AI', 'major'],
        'categories': ['portfolio'],
        'timingPreferences': ['portfolio'],
        'teamPreferences': ['teamPreference', 'solo'],
        'uncertainties': [
          'major',
          'grade',
          'experienceLevel',
          'teamPreference',
        ],
      },
      'recommendations': [
        {
          'competitionId': 'comp_math_modeling',
          'reason': '你的需求适合数模。理由基于候选竞赛事实。',
          'preparationTips': <String>[],
          'limitations': <String>[],
          'matchScore': 0.8,
        },
      ],
      'followUpQuestions': <String>[],
    });
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(Success(content)),
      candidates: source,
    );

    final data = (await repo.getRecommendations(prompt: 'x') as Success).data;
    final visible = [
      ...data.understanding.directions,
      ...data.understanding.categories,
      ...data.understanding.timingPreferences,
      ...data.understanding.teamPreferences,
      ...data.understanding.uncertainties,
    ];

    expect(visible, isNot(contains('portfolio')));
    expect(visible, isNot(contains('major')));
    expect(visible, isNot(contains('experienceLevel')));
    expect(visible, isNot(contains('teamPreference')));
    expect(data.understanding.directions, ['AI']);
    expect(data.understanding.categories, isEmpty);
    expect(data.understanding.timingPreferences, isEmpty);
    expect(data.understanding.teamPreferences, ['个人赛']);
    expect(
      data.understanding.uncertainties,
      containsAll(['未明确专业', '未明确年级', '未明确竞赛经验', '未明确组队偏好']),
    );
  });

  test('uses JSON mode', () async {
    final fake = _FakeLlm(const Success('{"recommendations":[]}'));
    final repo = AiCompetitionRecommendationRepository(
      llm: fake,
      candidates: source,
    );

    await repo.getRecommendations(prompt: 'x');

    expect(fake.lastJsonMode, isTrue);
  });

  test('grounding drops competitionId outside candidate pool', () async {
    final content = jsonEncode({
      'recommendations': [
        {
          'competitionId': 'comp_fake',
          'reason': '伪造',
          'preparationTips': <String>[],
          'limitations': <String>[],
          'matchScore': 0.9,
        },
        {
          'competitionId': 'comp_math_modeling',
          'reason': '真实候选',
          'preparationTips': <String>[],
          'limitations': <String>[],
          'matchScore': 0.8,
        },
      ],
    });
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(Success(content)),
      candidates: source,
    );

    final data = (await repo.getRecommendations(prompt: 'x') as Success).data;

    expect(data.recommendations.map((r) => r.id), ['comp_math_modeling']);
  });

  test('empty recommendations is successful', () async {
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(const Success('{"recommendations":[]}')),
      candidates: source,
    );

    final result = await repo.getRecommendations(prompt: 'x');

    expect((result as Success).data.recommendations, isEmpty);
  });

  test('malformed JSON returns ServerException failure', () async {
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(const Success('not json')),
      candidates: source,
    );

    final result = await repo.getRecommendations(prompt: 'x');

    expect((result as Failure).error, isA<ServerException>());
  });

  test('LLM failure passes through', () async {
    final repo = AiCompetitionRecommendationRepository(
      llm: _FakeLlm(const Failure(NetworkException())),
      candidates: source,
    );

    final result = await repo.getRecommendations(prompt: 'x');

    expect((result as Failure).error, isA<NetworkException>());
  });

  test('missing LLM configuration is explicit failure', () async {
    final repo = AiCompetitionRecommendationRepository(
      llm: const MissingLlmClient(),
      candidates: source,
    );

    final result = await repo.getRecommendations(prompt: '数学建模');

    expect((result as Failure).error, isA<MissingLlmConfigurationException>());
  });

  test('profile is included in user message when provided', () async {
    final fake = _FakeLlm(const Success('{"recommendations":[]}'));
    final repo = AiCompetitionRecommendationRepository(
      llm: fake,
      candidates: source,
    );

    await repo.getRecommendations(
      prompt: '推荐竞赛',
      profile: const UserProfile(
        major: '统计学',
        competitions: [Competition(name: '校级数学建模竞赛', award: '一等奖')],
      ),
    );

    expect(fake.lastUserContent, contains('【学生档案】'));
    expect(fake.lastUserContent, contains('校级数学建模竞赛'));
  });
}
