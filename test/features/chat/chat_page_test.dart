import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/features/chat/pages/chat_page.dart';

import '../../helpers/fake_conversation_repository.dart';

const _config = AppConfig(
  dataSource: DataSource.llm,
  llm: LlmConfig(apiKey: 'test-key'),
);

Widget _wrap(
  ControllableConversationRepository repo, {
  AppConfig config = _config,
  Widget? chatPage,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => chatPage ?? const ChatPage(sessionId: 's_test'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home-marker')),
      GoRoute(path: '/professor/:id', builder: (_, _) => const Placeholder()),
    ],
  );
  return ProviderScope(
    overrides: [
      initialAppConfigProvider.overrideWithValue(config),
      conversationRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets('挂载后恢复会话并显示输入区', (tester) async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(session: fakeSession(id: 's_test')),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(repo));
    await _pumpFrames(tester);

    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(repo.loadCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('已恢复历史消息会渲染为气泡内容', (tester) async {
    final user = fakeUserMessage(content: '为什么推荐他');
    final assistant = fakeAssistantMessage(content: '因为方向匹配');
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(
        session: fakeSession(id: 's_test', revision: 1),
        turns: [
          fakeTurn(
            sessionId: 's_test',
            status: ConversationTurnStatus.completed,
            userMessage: user,
          ),
        ],
        messages: [user, assistant],
      ),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(repo));
    await _pumpFrames(tester);

    expect(find.text('为什么推荐他'), findsOneWidget);
    expect(find.text('因为方向匹配'), findsOneWidget);
    expect(find.byTooltip('重新生成'), findsWidgets);
  });

  testWidgets('推荐消息渲染推荐卡并保留导师入口', (tester) async {
    const rec = Recommendation(
      professorId: 'p_001',
      name: '张三',
      university: '清华大学',
      college: '计算机系',
      title: '教授',
      researchFields: ['计算机视觉'],
      matchLevel: MatchLevel.high,
      reason: '方向契合',
      limitations: [],
    );
    final user = fakeUserMessage(content: '想做计算机视觉');
    final assistant = fakeAssistantMessage(
      content: '为你挑了合适的导师',
      kind: ChatMessageKind.recommendation,
      relatedRecommendations: const [rec],
    );
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(
        session: fakeSession(id: 's_test', revision: 1),
        turns: [
          fakeTurn(
            sessionId: 's_test',
            status: ConversationTurnStatus.completed,
            route: ConversationRoute.recommendation,
            userMessage: user,
          ),
        ],
        messages: [user, assistant],
      ),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(repo));
    await _pumpFrames(tester);

    expect(find.text('为你挑了合适的导师'), findsOneWidget);
    expect(find.text('张三'), findsWidgets);
  });

  testWidgets('无 sessionId 时创建新会话但不自动发送', (tester) async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(session: fakeSession(id: 'session-1')),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(repo, chatPage: const ChatPage()));
    await _pumpFrames(tester);

    expect(repo.createCalls, 1);
    expect(repo.submitCalls, isEmpty);
    expect(find.byTooltip('发送'), findsOneWidget);
  });

  testWidgets('发送后首个 SSE 事件返回前显示正在思考', (tester) async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(session: fakeSession(id: 's_test')),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(repo));
    await _pumpFrames(tester);

    await tester.enterText(find.byType(TextField), '真实后端问题');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();

    expect(repo.submitCalls, hasLength(1));
    expect(find.text('真实后端问题'), findsOneWidget);
    expect(find.text('正在思考'), findsOneWidget);

    await repo.closeActiveEvents();
    await tester.pump();
  });

  testWidgets('未配置 LLM Key 时直达聊天页显示错误且不请求会话', (tester) async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(session: fakeSession(id: 's_test')),
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(
      _wrap(repo, config: const AppConfig(dataSource: DataSource.llm)),
    );
    await _pumpFrames(tester);

    expect(
      find.text(const MissingLlmConfigurationException().message),
      findsOneWidget,
    );
    expect(repo.loadCalls, 0);
    expect(repo.createCalls, 0);
  });
}
