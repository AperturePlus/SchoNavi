import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/launcher/link_launcher.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/competition_recommendation_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/features/home/pages/home_page.dart';

class _FakeCompetitionRepo implements CompetitionRecommendationRepository {
  int calls = 0;

  @override
  Future<Result<CompetitionRecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async {
    calls++;
    return Success(
      CompetitionRecommendationResult(
        sessionId: 's-test',
        understanding: const CompetitionQueryUnderstanding(
          directions: ['算法'],
          categories: [],
          timingPreferences: [],
          teamPreferences: [],
          uncertainties: [],
        ),
        recommendations: [
          RecommendedCompetition(
            id: 'c0',
            name: '原地竞赛卡',
            category: '计算机类',
            level: '国家级',
            tags: const ['算法'],
            teamSize: '个人',
            signupTime: '',
            contestTime: '',
            format: '',
            organizer: '',
            officialUrl: null,
            reason: '契合你的算法方向',
            preparationTips: const [],
            limitations: const [],
            matchScore: 0.75,
          ),
        ],
        followUpQuestions: const [],
      ),
    );
  }
}

class _FakeHistoryRepo implements HistoryRepository {
  _FakeHistoryRepo({List<SearchHistoryItem> items = const []})
    : _items = List.of(items);

  final List<SearchHistoryItem> _items;

  @override
  List<SearchHistoryItem> list() => List.unmodifiable(_items);

  @override
  Stream<List<SearchHistoryItem>> watch() => Stream.value(list());

  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async {
    for (final item in _items) {
      if (item.sessionId == sessionId && (type == null || item.type == type)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {}

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {
    _items.add(
      SearchHistoryItem(
        type: SearchHistoryType.competition,
        sessionId: result.sessionId,
        prompt: prompt,
        createdAt: DateTime.utc(2026, 6, 15, 10),
        summary: '方向：算法',
        researchInterests: const ['算法'],
        preferredLocations: const [],
        recommendationCount: result.recommendations.length,
        competitionResult: result,
      ),
    );
  }

  @override
  Future<void> remove(String sessionId) async {}

  @override
  Future<void> clear() async {}
}

class _FakeLinkLauncher implements LinkLauncher {
  @override
  Future<LaunchResult> open(String? url) async => LaunchResult.success;
}

Future<Widget> _wrap({
  String initialLocation = '/',
  _FakeCompetitionRepo? competitionRepo,
  _FakeHistoryRepo? historyRepo,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/home',
        builder: (_, state) {
          final tab = state.uri.queryParameters['tab'];
          return HomePage(
            initialTab: tab == 'competition'
                ? HomeTab.competition
                : HomeTab.mentor,
            historySessionId: state.uri.queryParameters['historySid'],
          );
        },
      ),
      GoRoute(path: '/competition/:id', builder: (_, _) => const Placeholder()),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(
        const AppConfig(llm: LlmConfig(apiKey: 'test-key')),
      ),
      competitionRecommendationRepositoryProvider.overrideWithValue(
        competitionRepo ?? _FakeCompetitionRepo(),
      ),
      historyRepositoryProvider.overrideWithValue(
        historyRepo ?? _FakeHistoryRepo(),
      ),
      linkLauncherProvider.overrideWithValue(_FakeLinkLauncher()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

SearchHistoryItem _historyItem({bool withResult = true}) => SearchHistoryItem(
  type: SearchHistoryType.competition,
  sessionId: 'c_history',
  prompt: '历史里的算法竞赛',
  createdAt: DateTime.utc(2026, 6, 15, 10),
  summary: '方向：算法 / 类别：计算机类',
  researchInterests: const ['算法', '计算机类'],
  preferredLocations: const [],
  recommendationCount: 1,
  competitionResult: withResult ? _historyCompetitionResult : null,
);

const _historyCompetitionResult = CompetitionRecommendationResult(
  sessionId: 'c_history',
  understanding: CompetitionQueryUnderstanding(
    directions: ['算法'],
    categories: ['计算机类'],
    timingPreferences: [],
    teamPreferences: [],
    uncertainties: [],
  ),
  recommendations: [
    RecommendedCompetition(
      id: 'c_history_card',
      name: '历史竞赛卡',
      category: '计算机类',
      level: '国家级',
      tags: ['算法'],
      teamSize: '个人',
      signupTime: '',
      contestTime: '',
      format: '',
      organizer: '',
      officialUrl: null,
      reason: '来自历史结果',
      preparationTips: [],
      limitations: [],
      matchScore: 0.88,
    ),
  ],
  followUpQuestions: [],
);

void main() {
  testWidgets('竞赛 tab 提交后原地展示推荐卡，不跳路由', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    // 切换到竞赛 tab。
    await tester.tap(find.text('竞赛'));
    await tester.pumpAndSettle();

    // 输入文本并提交。
    await tester.enterText(find.byType(TextField), '我想参加算法竞赛');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    // 原地展示竞赛推荐卡及调整条件按钮，不跳独立结果页。
    expect(find.text('原地竞赛卡'), findsOneWidget);
    expect(find.text('调整条件'), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('带 historySid 打开竞赛 tab 恢复历史卡片，不重新推荐', (tester) async {
    final competitionRepo = _FakeCompetitionRepo();
    await tester.pumpWidget(
      await _wrap(
        initialLocation: '/home?tab=competition&historySid=c_history',
        competitionRepo: competitionRepo,
        historyRepo: _FakeHistoryRepo(items: [_historyItem()]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史里的算法竞赛', skipOffstage: false), findsOneWidget);
    expect(find.text('历史竞赛卡'), findsOneWidget);
    expect(find.text('原地竞赛卡'), findsNothing);
    expect(competitionRepo.calls, 0);
  });

  testWidgets('老竞赛历史无 competitionResult 时显示摘要和重新生成', (tester) async {
    final competitionRepo = _FakeCompetitionRepo();
    await tester.pumpWidget(
      await _wrap(
        initialLocation: '/home?tab=competition&historySid=c_history',
        competitionRepo: competitionRepo,
        historyRepo: _FakeHistoryRepo(items: [_historyItem(withResult: false)]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史里的算法竞赛', skipOffstage: false), findsOneWidget);
    expect(find.text('方向：算法 / 类别：计算机类'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('历史竞赛卡'), findsNothing);
    expect(competitionRepo.calls, 0);
  });
}
