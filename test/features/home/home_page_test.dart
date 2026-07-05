import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/chat_result.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/fork_ref.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/repositories/chat_repository.dart';
import 'package:scho_navi/domain/repositories/competition_recommendation_repository.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/domain/repositories/recommendation_repository.dart';
import 'package:scho_navi/features/home/pages/home_page.dart';
import 'package:scho_navi/shared/utils/recommendation_need_classifier.dart';
import 'package:scho_navi/shared/widgets/swipe_recommendation_card.dart';

final _recResult = RecommendationResult(
  sessionId: 's_rec',
  queryUnderstanding: const QueryUnderstanding(
    researchInterests: ['医学影像'],
    preferredLocations: ['上海'],
    preferredUniversities: [],
    degreeStage: null,
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
  followUpQuestions: const ['偏应用'],
);

final _compResult = CompetitionRecommendationResult(
  sessionId: 's_comp',
  understanding: const CompetitionQueryUnderstanding(
    directions: ['算法'],
    categories: [],
    timingPreferences: [],
    teamPreferences: [],
    uncertainties: [],
  ),
  recommendations: [
    RecommendedCompetition(
      id: 'c_001',
      name: '蓝桥杯',
      category: '计算机类',
      level: '国家级',
      tags: const ['算法'],
      teamSize: '个人',
      signupTime: '',
      contestTime: '',
      format: '',
      organizer: '',
      officialUrl: null,
      reason: '契合算法方向',
      preparationTips: const [],
      limitations: const [],
      matchScore: 0.8,
    ),
  ],
  followUpQuestions: const [],
);

class _FakeRecRepo implements RecommendationRepository {
  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async => Success(_recResult);
}

class _FakeCompetitionRepo implements CompetitionRecommendationRepository {
  @override
  Future<Result<CompetitionRecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async => Success(_compResult);
}

class _StreamChatRepo implements ChatRepository {
  @override
  Future<Result<ChatResult>> sendMessage({
    required String sessionId,
    required String message,
    String? professorId,
  }) async => throw UnimplementedError();
  @override
  Future<void> seedRecommendationTurn({
    required String sessionId,
    required String userPrompt,
    required RecommendationResult result,
  }) async {}
  @override
  Future<void> persistMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {}
  @override
  Stream<String> streamReply({
    required String sessionId,
    required String message,
    String? professorId,
  }) => Stream.fromIterable(const ['流式回答']);

  @override
  Future<Result<String>> forkSession({
    required String sourceSessionId,
    required String professorId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<ChatMessage>>> loadHistory({
    required String sessionId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<List<ForkRef>>> listForks({
    required String mainSessionId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<void>> deleteFork({required String forkId}) async =>
      throw UnimplementedError();
}

class _FakeNeedClassifier implements RecommendationNeedClassifier {
  const _FakeNeedClassifier();
  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) async => false;
}

class _FakeConversationRepo implements ConversationRepository {
  ConversationSession? _session;
  ConversationTurn? _turn;
  List<ChatMessage> _messages = const [];

  @override
  Future<Result<ConversationSession>> createSession({String? professorId}) async {
    final now = DateTime(2026, 6, 30, 10);
    final session = ConversationSession(
      id: 'home-session',
      kind: ConversationSessionKind.general,
      rootSessionId: 'home-session',
      ownerId: 'local',
      revision: 0,
      createdAt: now,
      updatedAt: now,
      title: '导师推荐',
      professorId: professorId,
    );
    _session = session;
    _messages = const [];
    _turn = null;
    return Success(session);
  }

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async {
    final session = _session;
    if (session == null || session.id != sessionId) {
      return Failure(UnknownException());
    }
    return Success(
      ConversationAggregate(
        session: session,
        turns: [?_turn],
        messages: _messages,
      ),
    );
  }

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) async* {
    final session = _session;
    if (session == null) return;
    final now = DateTime(2026, 6, 30, 10, 1);
    const turnId = 'turn-1';
    const attemptId = 'attempt-1';
    final user = ChatMessage(
      id: 'user-1',
      role: ChatRole.user,
      content: text,
      createdAt: now,
      relatedRecommendations: const [],
      status: ChatMessageStatus.done,
    );
    final assistant = ChatMessage(
      id: 'assistant-1',
      role: ChatRole.assistant,
      content: '为你找到这些导师：',
      createdAt: now,
      relatedRecommendations: _recResult.recommendations,
      status: ChatMessageStatus.done,
      kind: ChatMessageKind.recommendation,
    );
    _turn = ConversationTurn(
      id: turnId,
      sessionId: sessionId,
      ordinal: 0,
      status: ConversationTurnStatus.completed,
      userMessage: user,
      route: ConversationRoute.recommendation,
      activeAttemptId: attemptId,
      createdAt: now,
      updatedAt: now,
    );
    _messages = [user, assistant];
    _session = ConversationSession(
      id: session.id,
      kind: session.kind,
      rootSessionId: session.rootSessionId,
      ownerId: session.ownerId,
      revision: expectedRevision + 1,
      createdAt: session.createdAt,
      updatedAt: now,
      sourceSessionId: session.sourceSessionId,
      sourceTurnId: session.sourceTurnId,
      professorId: session.professorId,
      title: session.title,
      deletedAt: session.deletedAt,
      legacyContextIncomplete: session.legacyContextIncomplete,
    );

    yield const ConversationAcknowledged(
      sessionId: 'home-session',
      turnId: turnId,
      attemptId: attemptId,
      revision: 1,
    );
    yield const ConversationRouted(
      sessionId: 'home-session',
      turnId: turnId,
      attemptId: attemptId,
      revision: 1,
      route: ConversationRoute.recommendation,
    );
    yield ConversationCompleted(
      sessionId: 'home-session',
      turnId: turnId,
      attemptId: attemptId,
      revision: 1,
      message: assistant,
      session: _session!,
      quickActions: _recResult.followUpQuestions,
    );
  }

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => Failure(UnknownException());

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async => const Success(null);

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success([?_session]);

  @override
  Future<Result<List<ConversationSession>>> listForks(String rootSessionId) async =>
      const Success([]);

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    _session = null;
    _turn = null;
    _messages = const [];
    return const Success(null);
  }

  @override
  Future<Result<void>> clearSessions() async {
    _session = null;
    _turn = null;
    _messages = const [];
    return const Success(null);
  }
}

Future<Widget> _wrap({bool configured = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/chat',
        builder: (_, s) => Text('chat-marker:${s.uri.queryParameters['q']}'),
      ),
      GoRoute(path: '/professor/:id', builder: (_, _) => const Placeholder()),
      GoRoute(path: '/profile/wizard', builder: (_, _) => const Text('wizard')),
      GoRoute(path: '/profile', builder: (_, _) => const Text('profile')),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(
        AppConfig(llm: LlmConfig(apiKey: configured ? 'test-key' : '')),
      ),
      recommendationRepositoryProvider.overrideWithValue(_FakeRecRepo()),
      conversationRepositoryProvider.overrideWithValue(_FakeConversationRepo()),
      competitionRecommendationRepositoryProvider.overrideWithValue(
        _FakeCompetitionRepo(),
      ),
      chatRepositoryProvider.overrideWithValue(_StreamChatRepo()),
      recommendationNeedClassifierProvider.overrideWithValue(
        const _FakeNeedClassifier(),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('submit button disabled when input empty', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();
    final button = tester.widget<InkWell>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(InkWell),
      ),
    );
    expect(button.onTap, isNull);
  });

  testWidgets('submit button enabled after typing', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '我想找医学影像方向的导师');
    await tester.pump();
    final button = tester.widget<InkWell>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_upward),
        matching: find.byType(InkWell),
      ),
    );
    expect(button.onTap, isNotNull);
  });

  testWidgets('example prompt fills the input', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    final example = find.text('我想找计算机视觉方向的导师，最好在北京。');
    await tester.scrollUntilVisible(
      example,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(example);
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, '我想找计算机视觉方向的导师，最好在北京。');
  });

  testWidgets(
    'competition prompt stays home and shows in-place recommendation',
    (tester) async {
      await tester.pumpWidget(await _wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('竞赛'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '我想参加蓝桥杯');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      // 不跳路由：原地出现竞赛推荐卡 + 调整条件。
      expect(find.text('competition-marker'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('我想参加蓝桥杯', skipOffstage: false), findsOneWidget);
      expect(find.text('蓝桥杯'), findsOneWidget);
      expect(find.text('调整条件'), findsOneWidget);
    },
  );

  testWidgets('mentor prompt stays home and starts in-place conversation', (
    tester,
  ) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我想找医学影像方向的导师');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    // 不跳路由：原地出现用户消息 + 横滑推荐卡片，无 /chat 路由 marker。
    expect(find.textContaining('chat-marker:'), findsNothing);
    expect(find.text('我想找医学影像方向的导师', skipOffstage: false), findsOneWidget);
    expect(find.byType(SwipeRecommendationCard), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
  });

  testWidgets('mentor prompt without LLM key stays home and shows error', (
    tester,
  ) async {
    await tester.pumpWidget(await _wrap(configured: false));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    expect(container.read(appConfigProvider).llm.isConfigured, isFalse);

    await tester.enterText(find.byType(TextField), '我想找医学影像方向的导师');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('未配置 LLM_API_KEY'), findsOneWidget);
    // 未配置不进入对话态，仍停留在落地页。
    expect(find.textContaining('chat-marker:'), findsNothing);
    expect(find.byType(SwipeRecommendationCard), findsNothing);
  });

  testWidgets(
    'competition quick tag stays home and shows in-place recommendation',
    (tester) async {
      await tester.pumpWidget(await _wrap());
      await tester.pumpAndSettle();

      await tester.tap(find.text('竞赛'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('人工智能竞赛'));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      // 不跳路由：原地出现竞赛推荐卡 + 调整条件。
      expect(find.text('competition-marker'), findsNothing);
      expect(find.byType(HomePage), findsOneWidget);
      expect(find.text('蓝桥杯'), findsOneWidget);
      expect(find.text('调整条件'), findsOneWidget);
    },
  );

  testWidgets('right edge swipe opens the end drawer', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(Scaffold));
    await tester.flingFrom(
      Offset(size.width - 10, 200),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    expect(scaffoldState.isEndDrawerOpen, isTrue);
  });

  testWidgets('switching tab shows competition examples and tags', (
    tester,
  ) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('竞赛'));
    await tester.pumpAndSettle();

    expect(find.text('推荐近期可报名的人工智能竞赛。'), findsOneWidget);
    expect(find.text('人工智能竞赛'), findsOneWidget);
  });

  testWidgets('switching tab preserves input text', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '保留输入');
    await tester.pump();

    await tester.tap(find.text('竞赛'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('导师'));
    await tester.pumpAndSettle();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, '保留输入');
  });

  testWidgets('落地态：左上无新对话按钮，右上存在菜单按钮', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    // 落地态左上无「新对话」悬浮按钮。
    expect(find.byTooltip('新对话'), findsNothing);
    // 右上始终有「菜单」悬浮按钮。
    expect(find.byTooltip('菜单'), findsOneWidget);
    // 不再有 AppBar 实体栏。
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('对话态：左上出现新对话按钮，点击回到落地态', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我想找医学影像方向的导师');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    // 对话态左上「新对话」出现。
    expect(find.byTooltip('新对话'), findsOneWidget);
    // 点击回到落地态。
    await tester.tap(find.byTooltip('新对话'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('新对话'), findsNothing);
  });

  testWidgets('drawer shows feedback tile', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(Scaffold));
    await tester.flingFrom(
      Offset(size.width - 10, 200),
      const Offset(-200, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(find.text('反馈'), findsOneWidget);
    expect(find.byTooltip('反馈'), findsOneWidget);
  });
}
