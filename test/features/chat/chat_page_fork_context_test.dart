import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/mock/mock_db.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/fork_ref.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/professor.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/domain/repositories/professor_repository.dart';
import 'package:scho_navi/features/chat/pages/chat_page.dart';

class _PendingConversationRepository implements ConversationRepository {
  _PendingConversationRepository(this.session);

  final ConversationSession session;
  final Completer<Result<ConversationAggregate>> load = Completer();

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => Success(session);

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) =>
      load.future;

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => Success(session);

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();

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
      Success([session]);

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => Success([session]);

  @override
  Future<Result<void>> deleteSession(String sessionId) async =>
      const Success(null);
}

class _ScriptedConversationRepository implements ConversationRepository {
  _ScriptedConversationRepository({
    required this.source,
    required this.fork,
  });

  final ConversationAggregate source;
  final ConversationAggregate fork;

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => Success(fork.session);

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async {
    if (sessionId == source.session.id) return Success(source);
    if (sessionId == fork.session.id) return Success(fork);
    return const Failure(NotFoundException());
  }

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => Success(fork.session);

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => const Stream.empty();

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
      Success([source.session]);

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => Success([fork.session]);

  @override
  Future<Result<void>> deleteSession(String sessionId) async =>
      const Success(null);
}

class _StaticProfessorRepository implements ProfessorRepository {
  const _StaticProfessorRepository(this.result);

  final Result<Professor> result;

  @override
  Future<Result<Professor>> getProfessor(String professorId) async => result;
}

Professor _professor(String id, String name) => Professor(
  id: id,
  name: name,
  university: '浙江大学',
  college: '计算机科学与技术学院',
  title: '教授',
  researchFields: const ['人工智能', '教育技术'],
);

Recommendation _recommendation(String id, String name) => Recommendation(
  professorId: id,
  name: name,
  university: '复旦大学',
  college: '计算机科学技术学院',
  title: '教授',
  researchFields: const ['多模态学习'],
  matchLevel: MatchLevel.high,
  reason: '研究方向与用户需求匹配。',
  limitations: const ['招生信息以官网为准'],
  matchScore: 0.9,
);

ConversationSession _session({
  required String id,
  required ConversationSessionKind kind,
  required DateTime now,
  String? rootSessionId,
  String? sourceSessionId,
  String? sourceTurnId,
  String? professorId,
}) => ConversationSession(
  id: id,
  kind: kind,
  rootSessionId: rootSessionId ?? id,
  sourceSessionId: sourceSessionId,
  sourceTurnId: sourceTurnId,
  professorId: professorId,
  ownerId: 'test',
  revision: 0,
  createdAt: now,
  updatedAt: now,
);

ConversationAggregate _emptyForkAggregate({
  required String forkId,
  required String professorId,
  required DateTime now,
}) {
  final session = _session(
    id: forkId,
    kind: ConversationSessionKind.fork,
    rootSessionId: 'main-1',
    sourceSessionId: 'main-1',
    sourceTurnId: 'source-turn',
    professorId: professorId,
    now: now,
  );
  return ConversationAggregate(
    session: session,
    turns: const [],
    messages: const [],
  );
}

ConversationAggregate _sourceAggregate({
  required Recommendation recommendation,
  required DateTime now,
}) {
  final session = _session(
    id: 'main-1',
    kind: ConversationSessionKind.general,
    now: now,
  );
  final user = ChatMessage(
    id: 'user-1',
    role: ChatRole.user,
    content: '我想找多模态学习方向导师',
    createdAt: now,
    relatedRecommendations: const [],
    status: ChatMessageStatus.done,
  );
  final assistant = ChatMessage(
    id: 'assistant-1',
    role: ChatRole.assistant,
    content: '这些导师比较匹配。',
    createdAt: now,
    relatedRecommendations: [recommendation],
    status: ChatMessageStatus.done,
    kind: ChatMessageKind.recommendation,
  );
  return ConversationAggregate(
    session: session,
    turns: [
      ConversationTurn(
        id: 'source-turn',
        sessionId: session.id,
        ordinal: 0,
        status: ConversationTurnStatus.completed,
        route: ConversationRoute.recommendation,
        userMessage: user,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    messages: [user, assistant],
  );
}

void main() {
  testWidgets('fork 加载时不闪通用欢迎卡，完成后显示教授专属引导', (tester) async {
    final now = DateTime.utc(2026, 6, 28);
    final professor = MockDb().getProfessor('p_001')!;
    final session = ConversationSession(
      id: 'fork-1',
      kind: ConversationSessionKind.fork,
      rootSessionId: 'main-1',
      sourceSessionId: 'main-1',
      sourceTurnId: 'source-turn',
      professorId: professor.id,
      ownerId: 'local',
      revision: 0,
      createdAt: now,
      updatedAt: now,
    );
    final repository = _PendingConversationRepository(session);
    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repository),
        professorRepositoryProvider.overrideWithValue(
          _StaticProfessorRepository(Success(professor)),
        ),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatPage(forkMode: true, forkId: 'fork-1'),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('有什么想追问的？'), findsNothing);
    expect(find.textContaining('相似导师'), findsNothing);

    repository.load.complete(
      Success(
        ConversationAggregate(
          session: session,
          turns: const [],
          messages: const [],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('关于${professor.name}教授，想继续问什么？'), findsOneWidget);
    expect(
      find.text(
        '我会参考上一轮的需求与推荐依据，但这里仅显示围绕该教授的新对话。'
        '可以问：为什么适合我、研究方向、硕博匹配、联系前准备。',
      ),
      findsOneWidget,
    );
    expect(find.text('推荐计算机视觉导师'), findsNothing);
  });

  testWidgets('HTTP fork 用真实导师仓储显示远端导师名', (tester) async {
    final now = DateTime.utc(2026, 6, 28);
    const professorId = 'remote-prof-1';
    final professor = _professor(professorId, '陈远航');
    final fork = _emptyForkAggregate(
      forkId: 'fork-remote',
      professorId: professorId,
      now: now,
    );
    final repository = _PendingConversationRepository(fork.session);
    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repository),
        professorRepositoryProvider.overrideWithValue(
          _StaticProfessorRepository(Success(professor)),
        ),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatPage(forkMode: true, forkId: 'fork-remote'),
        ),
      ),
    );
    await tester.pump();

    repository.load.complete(Success(fork));
    await tester.pumpAndSettle();

    expect(find.text('陈远航 教授'), findsOneWidget);
    expect(find.text('关于陈远航教授，想继续问什么？'), findsOneWidget);
    expect(find.text('该导师 教授'), findsNothing);
  });

  testWidgets('startFork 在导师接口失败时使用源推荐快照', (tester) async {
    final now = DateTime.utc(2026, 6, 28);
    const professorId = 'remote-prof-2';
    final recommendation = _recommendation(professorId, '林海');
    final fork = _emptyForkAggregate(
      forkId: 'fork-from-source',
      professorId: professorId,
      now: now,
    );
    final repository = _ScriptedConversationRepository(
      source: _sourceAggregate(recommendation: recommendation, now: now),
      fork: fork,
    );
    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repository),
        professorRepositoryProvider.overrideWithValue(
          const _StaticProfessorRepository(Failure(NotFoundException())),
        ),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatPage(
            forkMode: true,
            mainSessionId: 'main-1',
            professorId: professorId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('林海 教授'), findsOneWidget);
    expect(find.text('关于林海教授，想继续问什么？'), findsOneWidget);
    expect(find.text(forkProfessorUnavailableLabel), findsNothing);
  });

  testWidgets('导师详情和推荐快照都缺失时显示不可用兜底', (tester) async {
    final now = DateTime.utc(2026, 6, 28);
    const professorId = 'remote-missing';
    final fork = _emptyForkAggregate(
      forkId: 'fork-missing',
      professorId: professorId,
      now: now,
    );
    final repository = _PendingConversationRepository(fork.session);
    final container = ProviderContainer(
      overrides: [
        conversationRepositoryProvider.overrideWithValue(repository),
        professorRepositoryProvider.overrideWithValue(
          const _StaticProfessorRepository(Failure(NotFoundException())),
        ),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatPage(forkMode: true, forkId: 'fork-missing'),
        ),
      ),
    );
    await tester.pump();

    repository.load.complete(Success(fork));
    await tester.pumpAndSettle();

    expect(find.text(forkProfessorUnavailableLabel), findsOneWidget);
    expect(find.text('$forkProfessorUnavailableLabel 教授'), findsNothing);
    expect(find.text('该导师 教授'), findsNothing);
    expect(find.text('有什么想追问的？'), findsOneWidget);
  });
}
