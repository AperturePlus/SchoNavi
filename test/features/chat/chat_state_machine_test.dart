import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/features/chat/providers/chat_provider.dart';

final _provider = chatProvider(Object());

class _FakeConversationRepository implements ConversationRepository {
  _FakeConversationRepository(this.aggregate);

  ConversationAggregate aggregate;
  Result<ConversationAggregate>? loadResult;
  final StreamController<ConversationEvent> events =
      StreamController<ConversationEvent>.broadcast();
  int createCalls = 0;
  int submitCalls = 0;
  int cancelCalls = 0;

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async {
    createCalls++;
    return Success(aggregate.session);
  }

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async =>
      loadResult ?? Success(aggregate);

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) {
    submitCalls++;
    return events.stream;
  }

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => events.stream;

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async {
    cancelCalls++;
    return const Success(null);
  }

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
  }) async => Success(aggregate.session);

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => const Success([]);

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success([aggregate.session]);

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);

  Future<void> close() => events.close();
}

ConversationSession _session({
  int revision = 0,
  bool legacyContextIncomplete = false,
}) {
  final now = DateTime.utc(2026, 6, 27);
  return ConversationSession(
    id: 'session-1',
    kind: ConversationSessionKind.general,
    rootSessionId: 'session-1',
    ownerId: 'local',
    revision: revision,
    createdAt: now,
    updatedAt: now,
    legacyContextIncomplete: legacyContextIncomplete,
  );
}

ChatMessage _message({
  required String id,
  required ChatRole role,
  required String content,
  ChatMessageStatus status = ChatMessageStatus.done,
}) => ChatMessage(
  id: id,
  role: role,
  content: content,
  createdAt: DateTime.utc(2026, 6, 27),
  relatedRecommendations: const [],
  status: status,
);

ConversationAggregate _emptyAggregate() => ConversationAggregate(
  session: _session(),
  turns: const [],
  messages: const [],
);

ProviderContainer _container(_FakeConversationRepository repository) {
  final container = ProviderContainer(
    overrides: [conversationRepositoryProvider.overrideWithValue(repository)],
  );
  container.listen(_provider, (_, _) {});
  return container;
}

void main() {
  test('加载失败进入 LoadFailed，绝不降级创建空会话', () async {
    final repository = _FakeConversationRepository(_emptyAggregate())
      ..loadResult = const Failure(NotFoundException());
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);

    await container.read(_provider.notifier).start(sessionId: 'missing');

    expect(container.read(_provider).activity, ChatActivity.loadFailed);
    expect(repository.createCalls, 0);
  });

  test(
    '合法事件按 Classifying → Connecting → Streaming → Committing → Idle',
    () async {
      final repository = _FakeConversationRepository(_emptyAggregate());
      final container = _container(repository);
      addTearDown(repository.close);
      addTearDown(container.dispose);
      final activities = <ChatActivity>[];
      container.listen(_provider, (_, next) => activities.add(next.activity));
      final notifier = container.read(_provider.notifier);
      await notifier.resume(sessionId: 'session-1');

      final pending = notifier.send('问题');
      await Future<void>.delayed(Duration.zero);
      repository.events.add(
        const ConversationAcknowledged(
          sessionId: 'session-1',
          turnId: 'turn-1',
          attemptId: 'attempt-1',
          revision: 0,
        ),
      );
      repository.events.add(
        const ConversationRouted(
          sessionId: 'session-1',
          turnId: 'turn-1',
          attemptId: 'attempt-1',
          revision: 0,
          route: ConversationRoute.conversation,
        ),
      );
      repository.events.add(
        const ConversationDelta(
          sessionId: 'session-1',
          turnId: 'turn-1',
          attemptId: 'attempt-1',
          revision: 0,
          text: '回答',
        ),
      );

      final user = _message(id: 'user-1', role: ChatRole.user, content: '问题');
      final assistant = _message(
        id: 'assistant-1',
        role: ChatRole.assistant,
        content: '回答',
      );
      final now = DateTime.utc(2026, 6, 27);
      final turn = ConversationTurn(
        id: 'turn-1',
        sessionId: 'session-1',
        ordinal: 0,
        status: ConversationTurnStatus.completed,
        route: ConversationRoute.conversation,
        userMessage: user,
        activeAttemptId: 'attempt-1',
        createdAt: now,
        updatedAt: now,
      );
      repository.aggregate = ConversationAggregate(
        session: _session(revision: 1),
        turns: [turn],
        messages: [user, assistant],
      );
      repository.events.add(
        ConversationCompleted(
          sessionId: 'session-1',
          turnId: 'turn-1',
          attemptId: 'attempt-1',
          revision: 1,
          message: assistant,
          session: repository.aggregate.session,
        ),
      );
      await repository.events.close();
      await pending;

      expect(
        activities,
        containsAllInOrder([
          ChatActivity.classifying,
          ChatActivity.connecting,
          ChatActivity.streaming,
          ChatActivity.committing,
          ChatActivity.idle,
        ]),
      );
      expect(container.read(_provider).revision, 1);
      expect(container.read(_provider).messages.last.content, '回答');
    },
  );

  test('不匹配 attempt 的旧增量不能写入当前状态', () async {
    final repository = _FakeConversationRepository(_emptyAggregate());
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);
    final notifier = container.read(_provider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('问题');
    await Future<void>.delayed(Duration.zero);
    repository.events.add(
      const ConversationAcknowledged(
        sessionId: 'session-1',
        turnId: 'turn-1',
        attemptId: 'attempt-current',
        revision: 0,
      ),
    );
    repository.events.add(
      const ConversationDelta(
        sessionId: 'session-1',
        turnId: 'turn-1',
        attemptId: 'attempt-old',
        revision: 0,
        text: '过期内容',
      ),
    );
    await repository.events.close();
    await pending;

    final state = container.read(_provider);
    expect(state.activity, ChatActivity.idle);
    expect(
      state.messages.any((message) => message.content.contains('过期内容')),
      isFalse,
    );
  });

  test('活动 turn 存在时并发发送被拒绝', () async {
    final repository = _FakeConversationRepository(_emptyAggregate());
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);
    final notifier = container.read(_provider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final first = notifier.send('第一个问题');
    await Future<void>.delayed(Duration.zero);
    await notifier.send('第二个问题');
    expect(repository.submitCalls, 1);

    await repository.events.close();
    await first;
  });

  test('重启加载 interrupted 后必须显式放弃才恢复发送', () async {
    final user = _message(id: 'user-1', role: ChatRole.user, content: '问题');
    final partial = _message(
      id: 'assistant-1',
      role: ChatRole.assistant,
      content: '部分内容',
      status: ChatMessageStatus.interrupted,
    );
    final now = DateTime.utc(2026, 6, 27);
    final aggregate = ConversationAggregate(
      session: _session(revision: 1),
      turns: [
        ConversationTurn(
          id: 'turn-1',
          sessionId: 'session-1',
          ordinal: 0,
          status: ConversationTurnStatus.interrupted,
          route: ConversationRoute.conversation,
          userMessage: user,
          activeAttemptId: 'attempt-1',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      messages: [user, partial],
    );
    final repository = _FakeConversationRepository(aggregate);
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);

    final notifier = container.read(_provider.notifier);
    await notifier.resume(sessionId: 'session-1');
    expect(container.read(_provider).activity, ChatActivity.interrupted);
    expect(container.read(_provider).canSend, isFalse);

    await notifier.abandonInterruptedTurn();
    expect(container.read(_provider).activity, ChatActivity.idle);
    expect(container.read(_provider).canSend, isTrue);
  });

  test('来源不可推断的旧会话只能读取，不能继续发送', () async {
    final repository = _FakeConversationRepository(
      ConversationAggregate(
        session: _session(legacyContextIncomplete: true),
        turns: const [],
        messages: const [],
      ),
    );
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);

    await container.read(_provider.notifier).resume(sessionId: 'session-1');
    expect(container.read(_provider).legacyContextIncomplete, isTrue);
    expect(container.read(_provider).canSend, isFalse);
    await container.read(_provider.notifier).send('不能写入');
    expect(repository.submitCalls, 0);
  });

  test('删除会话严格经过 Deleting → Deleted', () async {
    final repository = _FakeConversationRepository(_emptyAggregate());
    final container = _container(repository);
    addTearDown(repository.close);
    addTearDown(container.dispose);
    final activities = <ChatActivity>[];
    container.listen(_provider, (_, next) => activities.add(next.activity));

    final notifier = container.read(_provider.notifier);
    await notifier.resume(sessionId: 'session-1');
    await notifier.delete();

    expect(
      activities,
      containsAllInOrder([ChatActivity.deleting, ChatActivity.deleted]),
    );
    expect(container.read(_provider).messages, isEmpty);
  });
}
