import 'dart:convert';

import '../../core/ai/llm_client.dart';
import '../../core/error/app_exception.dart';
import '../../core/result/result.dart';
import '../../domain/entities/competition_query_understanding.dart';
import '../../domain/entities/competition_recommendation_result.dart';
import '../../domain/entities/recommended_competition.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/competition_recommendation_repository.dart';
import '../../domain/services/competition_query_understanding_normalizer.dart';
import '../fixtures/competition_catalog.dart';

class AiCompetitionRecommendationRepository
    implements CompetitionRecommendationRepository {
  AiCompetitionRecommendationRepository({
    required this.llm,
    required this.candidates,
  });

  final LlmClient llm;
  final CompetitionCandidateSource candidates;

  @override
  Future<Result<CompetitionRecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async {
    final pool = candidates.candidatesFor(prompt);
    final profileSection = _encodeProfile(profile);
    final result = await llm.complete(
      messages: [
        const LlmMessage('system', _systemPrompt),
        LlmMessage(
          'user',
          '【用户需求】$prompt\n'
              '${profileSection == null ? '' : '【学生档案】$profileSection\n'}'
              '【候选竞赛】${_encodeCandidates(pool)}',
        ),
      ],
      jsonMode: true,
      temperature: 0.25,
    );

    if (result is Failure<String>) return Failure(result.error);

    try {
      return Success(
        _parse(
          (result as Success<String>).data,
          pool,
          sessionId ?? 'c_${prompt.hashCode.toUnsigned(20)}',
        ),
      );
    } catch (_) {
      return const Failure(ServerException());
    }
  }

  String _encodeCandidates(List<RecommendedCompetition> pool) {
    return jsonEncode([
      for (final c in pool)
        {
          'id': c.id,
          'name': c.name,
          'category': c.category,
          'level': c.level,
          'tags': c.tags,
          'teamSize': c.teamSize,
          'signupTime': c.signupTime,
          'contestTime': c.contestTime,
          'format': c.format,
          'organizer': c.organizer,
          if (c.officialUrl != null) 'officialUrl': c.officialUrl,
          if (c.preparationTips.isNotEmpty)
            'preparationHints': c.preparationTips,
          if (c.limitations.isNotEmpty) 'knownLimitations': c.limitations,
        },
    ]);
  }

  String? _encodeProfile(UserProfile? p) {
    if (p == null || p.isEmpty) return null;
    return jsonEncode({
      if (p.gender != null) 'gender': p.gender!.name,
      if (p.degreeStage != null) 'degreeStage': p.degreeStage,
      if (p.targetDegree != null) 'targetDegree': p.targetDegree,
      if (p.school != null) 'school': p.school,
      if (p.major != null) 'major': p.major,
      if (p.score != null && !p.score!.isEmpty)
        'score': {
          if (p.score!.gpa != null) 'gpa': p.score!.gpa,
          if (p.score!.scale != null) 'scale': p.score!.scale,
          if (p.score!.rank != null) 'rank': p.score!.rank,
        },
      if (p.researchInterests.isNotEmpty)
        'researchInterests': p.researchInterests,
      if (p.competitions.isNotEmpty)
        'competitions': [for (final c in p.competitions) c.toJson()],
      if (p.research.isNotEmpty)
        'research': [for (final r in p.research) r.toJson()],
      if (p.highlights != null) 'highlights': p.highlights,
    });
  }

  CompetitionRecommendationResult _parse(
    String content,
    List<RecommendedCompetition> pool,
    String sessionId,
  ) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) throw const FormatException();

    final byId = {for (final c in pool) c.id: c};
    final understanding =
        decoded['understanding'] as Map<String, dynamic>? ?? const {};

    return CompetitionRecommendationResult(
      sessionId: sessionId,
      understanding: CompetitionQueryUnderstandingNormalizer.normalize(
        CompetitionQueryUnderstanding(
          directions: _strings(understanding['directions']),
          categories: _strings(understanding['categories']),
          timingPreferences: _strings(understanding['timingPreferences']),
          teamPreferences: _strings(understanding['teamPreferences']),
          uncertainties: _strings(understanding['uncertainties']),
        ),
      ),
      recommendations: _recommendations(decoded['recommendations'], byId),
      followUpQuestions: _strings(decoded['followUpQuestions']),
    );
  }

  List<RecommendedCompetition> _recommendations(
    Object? value,
    Map<String, RecommendedCompetition> byId,
  ) {
    final items = value as List? ?? const [];
    final recommendations = <RecommendedCompetition>[];

    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final id = _nullableString(item['competitionId'] ?? item['id']);
      final candidate = id == null ? null : byId[id];
      if (candidate == null) continue;

      final reason = _nullableString(item['reason']);
      if (reason == null) continue;

      recommendations.add(
        RecommendedCompetition(
          id: candidate.id,
          name: candidate.name,
          category: candidate.category,
          level: candidate.level,
          tags: candidate.tags,
          teamSize: candidate.teamSize,
          signupTime: candidate.signupTime,
          contestTime: candidate.contestTime,
          format: candidate.format,
          organizer: candidate.organizer,
          officialUrl: candidate.officialUrl,
          reason: reason,
          preparationTips: _strings(item['preparationTips']),
          limitations: _strings(item['limitations']),
          matchScore: _score(item['matchScore']),
        ),
      );
    }

    return recommendations;
  }

  List<String> _strings(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  double _score(Object? value) {
    final number = switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s),
      _ => null,
    };
    return (number ?? 0).clamp(0.0, 1.0).toDouble();
  }

  static const String _systemPrompt = '''
你是 SchoNavi 的竞赛推荐助手。根据【用户需求】和可选的【学生档案】，从【候选竞赛】中筛选并排序最适合的竞赛。
规则：
1. 只能推荐【候选竞赛】中出现的竞赛，用其 id 作为 competitionId；严禁编造竞赛、官网、报名时间或赛制。
2. 推荐理解、排序、理由、备赛建议都由你完成；不要要求客户端根据关键词补推荐。
3. 仅输出一个 JSON 对象，不要 Markdown、不要多余文字。
4. reason 用中文 2-3 句说明匹配点，可引用用户需求、学生档案和候选竞赛事实。
5. preparationTips 输出 1-4 条可执行备赛建议。
6. limitations 只写诚实注意事项，如“以官网最新通知为准”；不要编造具体名额、截止日期或获奖概率。
7. matchScore 为 0 到 1 的数字。
8. 若候选中无相关竞赛，recommendations 输出空数组。
9. understanding 中每个数组值必须是中文可展示短语；常见缩写可用 AI/CV/NLP/ICPC。
10. uncertainties 必须写成“未明确……”中文短语，禁止输出 major、grade、portfolio、experience_level、team_preference 等 schema 字段名或英文枚举 key。
输出格式：
{"understanding":{"directions":["人工智能"],"categories":["计算机类"],"timingPreferences":["近期可报名"],"teamPreferences":["团队赛"],"uncertainties":["未明确可投入时间"]},"recommendations":[{"competitionId":"comp_ai_creative","reason":"……","preparationTips":["……"],"limitations":["……"],"matchScore":0.86}],"followUpQuestions":["……"]}
''';
}
