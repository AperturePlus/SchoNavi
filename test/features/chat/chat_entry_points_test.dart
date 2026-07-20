import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/professor.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/professor_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/features/home/pages/home_page.dart';
import 'package:scho_navi/features/professor/pages/professor_page.dart';

import '../../helpers/fake_favorite_repository.dart';
import '../../helpers/stub_api_dio.dart';

class _FakeProfileRepo implements ProfileRepository {
  @override
  UserProfile load() => const UserProfile();
  @override
  Future<UserProfile> refresh() async => load();
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> clear() async {}
}

class _FakeProfessorRepo implements ProfessorRepository {
  @override
  Future<Result<Professor>> getProfessor(String id) async => const Success(
    Professor(
      id: 'p_001',
      name: '张三',
      university: '上海交通大学',
      college: '电子信息与电气工程学院',
      title: '教授',
      researchFields: ['医学影像'],
      bio: '研究医学影像。',
    ),
  );
}

class _FakeConversationRepo implements ConversationRepository {
  ConversationSession get session => ConversationSession(
    id: 'professor-session',
    kind: ConversationSessionKind.professor,
    rootSessionId: 'professor-session',
    professorId: 'p_001',
    ownerId: 'local',
    revision: 0,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => Success(session);
  @override
  Future<Result<void>> cancelAttempt(String attemptId) async =>
      const Success(null);
  @override
  Future<Result<void>> deleteSession(String sessionId) async =>
      const Success(null);
  @override
  Future<Result<void>> clearSessions() async => const Success(null);
  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => Success(session);
  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async =>
      Success(
        ConversationAggregate(
          session: session,
          turns: const [],
          messages: const [],
        ),
      );
  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => const Success([]);
  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success([session]);
  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();
  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);
  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();
}

Future<Widget> _wrapHome() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/chat',
        builder: (_, s) => Text('chat:${s.uri.queryParameters['sid']}'),
      ),
      GoRoute(path: '/professor/:id', builder: (_, _) => const Placeholder()),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
      conversationRepositoryProvider.overrideWithValue(_FakeConversationRepo()),
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      dioProvider.overrideWithValue(stubDio()),
      apiIdentityDioProvider.overrideWithValue(stubDio()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<Widget> _wrapProfessor() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const ProfessorPage(
          professorId: 'p_001',
          mainSessionId: 's_main_1',
        ),
      ),
      GoRoute(
        path: '/chat',
        builder: (_, s) => Text('chat:${s.uri.queryParameters['sid']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      conversationRepositoryProvider.overrideWithValue(_FakeConversationRepo()),
      professorRepositoryProvider.overrideWithValue(_FakeProfessorRepo()),
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<Widget> _wrapProfessorFromFork() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const ProfessorPage(
          professorId: 'p_001',
          mainSessionId: 's_main_1',
          sourceTurnId: 'turn_1',
          forkId: 'fork_existing',
        ),
      ),
      GoRoute(
        path: '/chat',
        builder: (_, s) => Text('chat:${s.uri.queryParameters['sid']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      conversationRepositoryProvider.overrideWithValue(_FakeConversationRepo()),
      professorRepositoryProvider.overrideWithValue(_FakeProfessorRepo()),
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('首页对话态不再有「继续追问」FAB', (tester) async {
    await tester.pumpWidget(await _wrapHome());
    await tester.pumpAndSettle();

    // 导师 tab：发送一条足够长的提示词，进入原地对话态。
    await tester.enterText(find.byType(TextField), '医学影像方向 上海交大');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.text('继续追问'), findsNothing);
  });

  testWidgets('无来源轮次时创建 professor 会话，再以 sid 跳 /chat', (tester) async {
    await tester.pumpWidget(await _wrapProfessor());
    await tester.pumpAndSettle();

    await tester.tap(find.text('咨询该导师'));
    await tester.pumpAndSettle();

    expect(find.text('chat:professor-session'), findsOneWidget);
  });

  testWidgets('从 fork 进入导师详情时继续追问回到原 fork', (tester) async {
    await tester.pumpWidget(await _wrapProfessorFromFork());
    await tester.pumpAndSettle();

    await tester.tap(find.text('继续追问'));
    await tester.pumpAndSettle();

    expect(find.text('chat:fork_existing'), findsOneWidget);
  });
}
