import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/theme/app_theme.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/shared/widgets/app_menu_drawer.dart';

Future<Widget> _pumpDrawer({
  List<ConversationSession> sessions = const [],
  ThemeMode themeMode = ThemeMode.light,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      initialAppConfigProvider.overrideWithValue(
        const AppConfig(dataSource: DataSource.llm),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      conversationRepositoryProvider.overrideWithValue(
        _FakeConversationRepo(sessions: sessions),
      ),
    ],
  );
  addTearDown(container.dispose);

  await container
      .read(historyRepositoryProvider)
      .addFromCompetitionResult(
        prompt: '数学建模 团队赛',
        result: _competitionResult(),
      );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              endDrawer: const AppMenuDrawer(),
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    child: const Text('Open drawer'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/chat',
            builder: (_, state) =>
                Text('chat:${state.uri.queryParameters['sid'] ?? ''}'),
          ),
          GoRoute(
            path: '/home',
            builder: (_, state) =>
                Text('home:tab=${state.uri.queryParameters['tab'] ?? ''}'),
          ),
        ],
      ),
    ),
  );
}

ConversationSession _mentorSession({
  String id = 's_1',
  String title = '医学影像 上海',
}) {
  final now = DateTime(2026, 6, 30, 10, 0);
  return ConversationSession(
    id: id,
    kind: ConversationSessionKind.general,
    rootSessionId: id,
    ownerId: 'local',
    revision: 1,
    createdAt: now,
    updatedAt: now,
    title: title,
  );
}

CompetitionRecommendationResult _competitionResult() =>
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

void main() {
  testWidgets('drawer shows 最近 section with mentor session', (tester) async {
    await tester.pumpWidget(await _pumpDrawer(sessions: [_mentorSession()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    expect(find.text('最近'), findsOneWidget);
    expect(find.text('医学影像 上海'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '上海');
    await tester.pumpAndSettle();
    expect(find.text('医学影像 上海'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '北京');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的最近搜索'), findsOneWidget);
    expect(find.text('医学影像 上海'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('医学影像 上海'), findsOneWidget);
  });

  testWidgets('mentor session in 最近 routes to /chat?sid=', (tester) async {
    await tester.pumpWidget(await _pumpDrawer(sessions: [_mentorSession()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('医学影像 上海'));
    await tester.pumpAndSettle();
    expect(find.text('chat:s_1'), findsOneWidget);
  });

  testWidgets('competition item in 最近 routes to competition page', (
    tester,
  ) async {
    await tester.pumpWidget(await _pumpDrawer());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('数学建模 团队赛'));
    await tester.pumpAndSettle();
    expect(find.text('home:tab=competition'), findsOneWidget);
  });

  testWidgets('drawer search matches competition label', (tester) async {
    await tester.pumpWidget(await _pumpDrawer(sessions: [_mentorSession()]));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '竞赛');
    await tester.pumpAndSettle();

    expect(find.text('数学建模 团队赛'), findsOneWidget);
    expect(find.text('医学影像 上海'), findsNothing);
  });

  testWidgets('抽屉含"我的备赛"入口', (tester) async {
    await tester.pumpWidget(await _pumpDrawer());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    expect(find.text('历史'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('我的备赛'), findsOneWidget);
    expect(find.text('反馈'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });

  testWidgets('dark drawer uses dark theme surfaces for contrast', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _pumpDrawer(
        sessions: [_mentorSession()],
        themeMode: ThemeMode.dark,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    final drawer = tester.widget<Drawer>(find.byType(Drawer));
    expect(drawer.backgroundColor, AppTheme.dark().colorScheme.surface);

    final historyTileMaterial = tester.widgetList<Material>(
      find.ancestor(
        of: find.text('医学影像 上海'),
        matching: find.byType(Material),
      ),
    ).firstWhere((material) => material.color == Colors.transparent);
    expect(historyTileMaterial.borderRadius, BorderRadius.circular(8));
  });
}

class _FakeConversationRepo implements ConversationRepository {
  _FakeConversationRepo({List<ConversationSession> sessions = const []})
    : _sessions = List.of(sessions);

  final List<ConversationSession> _sessions;

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async =>
      throw UnimplementedError();

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => throw UnimplementedError();

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async =>
      const Success(null);

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success(List.unmodifiable(_sessions));

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => const Success([]);

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    _sessions.removeWhere((session) => session.id == sessionId);
    return const Success(null);
  }

  @override
  Future<Result<void>> clearSessions() async {
    _sessions.clear();
    return const Success(null);
  }
}
