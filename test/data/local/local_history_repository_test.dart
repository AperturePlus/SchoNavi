import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/storage/shared_preferences_local_store.dart';
import 'package:scho_navi/data/local/local_history_repository.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';

void main() {
  late SharedPreferencesLocalStore store;
  late LocalHistoryRepository repo;
  var currentTime = DateTime(2026, 6, 8, 10);

  RecommendationResult result(String sessionId) => RecommendationResult(
    sessionId: sessionId,
    queryUnderstanding: const QueryUnderstanding(
      researchInterests: ['医学影像'],
      preferredLocations: ['上海'],
      preferredUniversities: [],
      degreeStage: '硕士',
      uncertainties: [],
    ),
    recommendations: const [
      Recommendation(
        professorId: 'p_001',
        name: '张三',
        university: '上海交通大学',
        college: '电子信息与电气工程学院',
        title: '教授',
        researchFields: ['医学影像'],
        matchLevel: MatchLevel.high,
        reason: '方向相关。',
        limitations: [],
      ),
    ],
    followUpQuestions: const [],
  );

  CompetitionRecommendationResult competitionResult(String sessionId) =>
      const CompetitionRecommendationResult(
        sessionId: 'c_1',
        understanding: CompetitionQueryUnderstanding(
          directions: ['数学建模'],
          categories: ['理学类'],
          timingPreferences: ['秋季/下半年'],
          teamPreferences: ['团队赛'],
          uncertainties: [],
        ),
        recommendations: [_competition],
        followUpQuestions: [],
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    store = SharedPreferencesLocalStore(prefs);
    repo = LocalHistoryRepository(store, now: () => currentTime);
  });

  tearDown(() => repo.dispose());

  test('addFromResult/remove/clear/list works', () async {
    await repo.addFromResult(prompt: '医学影像 上海', result: result('s_1'));
    expect(repo.list(), hasLength(1));
    expect(repo.list().single.type, SearchHistoryType.mentor);
    expect(repo.list().single.summary, '方向：医学影像 / 地区：上海');

    await repo.remove('s_1');
    expect(repo.list(), isEmpty);

    await repo.addFromResult(prompt: '医学影像 上海', result: result('s_1'));
    await repo.clear();
    expect(repo.list(), isEmpty);
  });

  test('addFromCompetitionResult stores competition history', () async {
    await repo.addFromCompetitionResult(
      prompt: '数学建模团队赛',
      result: competitionResult('c_1'),
    );

    final item = repo.list().single;
    expect(item.type, SearchHistoryType.competition);
    expect(item.sessionId, 'c_1');
    expect(item.recommendationCount, 1);
    expect(item.researchInterests, ['数学建模', '理学类']);
    expect(item.summary, '方向：数学建模 / 类别：理学类 / 时间：秋季/下半年 / 组队：团队赛');
    expect(item.competitionResult?.sessionId, 'c_1');
    expect(
      item.competitionResult?.recommendations.single.name,
      '全国大学生数学建模竞赛',
    );
  });

  test('same sessionId is deduped and updated', () async {
    currentTime = DateTime(2026, 6, 8, 10);
    await repo.addFromResult(prompt: '第一次', result: result('s_1'));
    currentTime = DateTime(2026, 6, 8, 11);
    await repo.addFromResult(prompt: '第二次', result: result('s_1'));

    final items = repo.list();
    expect(items, hasLength(1));
    expect(items.single.prompt, '第二次');
    expect(items.single.createdAt, DateTime(2026, 6, 8, 11));
  });

  test('watch emits current and changed lists', () async {
    final events = <List<SearchHistoryItem>>[];
    final sub = repo.watch().listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(Duration.zero);
    expect(events.single, isEmpty);

    await repo.addFromResult(prompt: '医学影像 上海', result: result('s_1'));
    await Future<void>.delayed(Duration.zero);

    expect(events.last.single.sessionId, 's_1');
  });

  test('bad json entries are ignored instead of crashing', () async {
    await store.setJsonList(LocalHistoryRepository.storageKey, <dynamic>[
      <String, dynamic>{'bad': true},
      <String, dynamic>{
        'session_id': 's_1',
        'prompt': '医学影像 上海',
        'created_at': '2026-06-08T10:00:00.000',
        'summary': '方向：医学影像 / 地区：上海',
        'research_interests': ['医学影像'],
        'preferred_locations': ['上海'],
        'recommendation_count': 1,
      },
    ]);

    final items = repo.list();
    expect(items, hasLength(1));
    expect(items.single.sessionId, 's_1');
    expect(items.single.type, SearchHistoryType.mentor);
    expect(items.single.competitionResult, isNull);
  });
}

const _competition = RecommendedCompetition(
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
  reason: '方向匹配。',
  preparationTips: ['训练论文写作'],
  limitations: ['以官网通知为准。'],
  matchScore: 0.91,
);
