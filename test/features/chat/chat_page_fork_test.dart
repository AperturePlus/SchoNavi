import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/data/mock/mock_db.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/features/chat/pages/chat_page.dart';
import 'package:scho_navi/features/chat/widgets/professor_anchor_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_conversation_repository.dart';

ConversationAggregate _sourceAggregate({
  required String sessionId,
  required String professorId,
}) {
  final user = fakeUserMessage(id: 'user-rec', content: '想做CV');
  final assistant = fakeAssistantMessage(
    id: 'assistant-rec',
    content: '为你挑了合适的导师',
    kind: ChatMessageKind.recommendation,
    relatedRecommendations: [
      Recommendation(
        professorId: professorId,
        name: '导师',
        university: '大学',
        college: '学院',
        title: '教授',
        researchFields: const ['计算机视觉'],
        matchLevel: MatchLevel.high,
        reason: '方向契合',
        limitations: const [],
      ),
    ],
  );
  return fakeAggregate(
    session: fakeSession(id: sessionId, revision: 1),
    turns: [
      fakeTurn(
        id: 'turn-rec',
        sessionId: sessionId,
        status: ConversationTurnStatus.completed,
        route: ConversationRoute.recommendation,
        userMessage: user,
      ),
    ],
    messages: [user, assistant],
  );
}

ControllableConversationRepository _forkRepo({
  required String sessionId,
  required String professorId,
}) {
  final repo = ControllableConversationRepository(
    initialAggregate: _sourceAggregate(sessionId: sessionId, professorId: professorId),
  );
  final source = _sourceAggregate(sessionId: sessionId, professorId: professorId);
  repo.setAggregate(
    fakeAggregate(
      session: fakeSession(
        id: 'fork-$sessionId-$professorId',
        kind: ConversationSessionKind.fork,
        rootSessionId: sessionId,
        sourceSessionId: sessionId,
        sourceTurnId: 'turn-rec',
        professorId: professorId,
        revision: 1,
      ),
      turns: source.turns,
      messages: source.messages,
    ),
  );
  return repo;
}

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}

void main() {
  testWidgets('fork 模式渲染锚点条', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const sessionId = 's1';
    final professorId = MockDb().allProfessors.first.id;
    final repo = _forkRepo(sessionId: sessionId, professorId: professorId);
    addTearDown(repo.dispose);

    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repo),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(
          path: '/chat',
          builder: (_, _) => UncontrolledProviderScope(
            container: container,
            child: ChatPage(
              forkMode: true,
              mainSessionId: sessionId,
              professorId: professorId,
            ),
          ),
        ),
        GoRoute(
          path: '/professor/:id',
          builder: (_, state) => Scaffold(
            body: Text('msid=${state.uri.queryParameters['msid'] ?? 'none'}'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpFrames(tester);
    expect(find.byType(ProfessorAnchorBar), findsOneWidget);
  });

  testWidgets('锚点条点击携带 mainSessionId 和 forkId 跳转到教授详情', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const sessionId = 's_main_42';
    final professorId = MockDb().allProfessors.first.id;
    final repo = _forkRepo(sessionId: sessionId, professorId: professorId);
    addTearDown(repo.dispose);

    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repo),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox()),
        GoRoute(
          path: '/chat',
          builder: (_, _) => UncontrolledProviderScope(
            container: container,
            child: ChatPage(
              forkMode: true,
              mainSessionId: sessionId,
              professorId: professorId,
            ),
          ),
        ),
        GoRoute(
          path: '/professor/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'msid=${state.uri.queryParameters['msid'] ?? 'none'};'
              'fid=${state.uri.queryParameters['fid'] ?? 'none'}',
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await _pumpFrames(tester);
    expect(find.byType(ProfessorAnchorBar), findsOneWidget);

    await tester.tap(find.byType(ProfessorAnchorBar));
    await _pumpFrames(tester);

    expect(find.textContaining('msid=$sessionId'), findsOneWidget);
    expect(find.textContaining('fid=fork-$sessionId-$professorId'), findsOneWidget);
  });
}
