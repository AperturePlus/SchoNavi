import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/features/chat/providers/chat_provider.dart';

import '../../helpers/fake_conversation_repository.dart';

final _chatTestProvider = chatProvider(Object());

ProviderContainer _containerWith(ControllableConversationRepository repo) {
  final container = ProviderContainer(
    overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(_chatTestProvider, (_, _) {});
  return container;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<void> _start(ProviderContainer container) async {
  await container
      .read(_chatTestProvider.notifier)
      .resume(sessionId: 'session-1');
}

Future<void> _sendToStreaming(
  ChatNotifier notifier,
  ControllableConversationRepository repo, {
  String text = '问题 1',
}) async {
  unawaited(notifier.send(text));
  await _flush();
  repo
    ..emit(acknowledged())
    ..emit(routed())
    ..emit(delta(text: '部分答案'));
  await _flush();
}

Future<void> _completeLatest(
  ChatNotifier notifier,
  ControllableConversationRepository repo, {
  String userText = '问题 1',
  String answer = '答案',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 1,
  List<String> quickActions = const [],
}) async {
  final pending = notifier.send(userText);
  await _flush();
  repo
    ..emit(acknowledged(turnId: turnId, attemptId: attemptId))
    ..emit(routed(turnId: turnId, attemptId: attemptId))
    ..emit(delta(turnId: turnId, attemptId: attemptId, text: answer));
  await _flush();

  final user = fakeUserMessage(id: 'user-$turnId', content: userText);
  final assistant = fakeAssistantMessage(
    id: 'assistant-$attemptId',
    content: answer,
  );
  final aggregate = fakeAggregate(
    session: fakeSession(revision: revision),
    turns: [
      fakeTurn(
        id: turnId,
        status: ConversationTurnStatus.completed,
        userMessage: user,
        activeAttemptId: attemptId,
      ),
    ],
    messages: [user, assistant],
  );
  repo.setAggregate(aggregate);
  repo.emit(
    completed(
      turnId: turnId,
      attemptId: attemptId,
      revision: revision,
      message: assistant,
      session: aggregate.session,
      quickActions: quickActions,
    ),
  );
  await repo.closeActiveEvents();
  await pending;
}

void main() {
  test('设置 feedback 成功，状态更新并同步仓储', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    await _completeLatest(notifier, repo);

    final assistantMessage = container.read(_chatTestProvider).messages.last;
    expect(assistantMessage.role, ChatRole.assistant);
    expect(assistantMessage.status, ChatMessageStatus.done);

    notifier.setFeedback(assistantMessage.id, ChatMessageFeedback.like);
    await _flush();

    final updated = container.read(_chatTestProvider).messages.last;
    expect(updated.id, assistantMessage.id);
    expect(updated.feedback, ChatMessageFeedback.like);
    expect(repo.feedbackCalls, [ChatMessageFeedback.like]);
  });

  test('对用户消息设置 feedback 无效', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    await _completeLatest(notifier, repo);

    final userMessage = container
        .read(_chatTestProvider)
        .messages
        .firstWhere((m) => m.role == ChatRole.user);

    notifier.setFeedback(userMessage.id, ChatMessageFeedback.like);
    await _flush();

    final unchanged = container
        .read(_chatTestProvider)
        .messages
        .firstWhere((m) => m.id == userMessage.id);
    expect(unchanged.feedback, ChatMessageFeedback.none);
    expect(repo.feedbackCalls, isEmpty);
  });

  test('对 streaming 中的助手消息设置 feedback 无效', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    await _sendToStreaming(notifier, repo);

    final assistantMessage = container.read(_chatTestProvider).messages.last;
    expect(assistantMessage.status, ChatMessageStatus.streaming);

    notifier.setFeedback(assistantMessage.id, ChatMessageFeedback.like);
    await _flush();

    final unchanged = container.read(_chatTestProvider).messages.last;
    expect(unchanged.feedback, ChatMessageFeedback.none);
    expect(repo.feedbackCalls, isEmpty);
    await repo.closeActiveEvents();
  });

  test('只能重新生成最新助手消息，旧消息请求被忽略', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    await _completeLatest(notifier, repo, turnId: 'turn-1', attemptId: 'a-1');
    final firstAssistantId = container.read(_chatTestProvider).messages.last.id;

    final user2 = fakeUserMessage(id: 'user-turn-2', content: '问题 2');
    final assistant2 = fakeAssistantMessage(
      id: 'assistant-a-2',
      content: '答案 2',
    );
    repo.setAggregate(
      fakeAggregate(
        session: fakeSession(revision: 2),
        turns: [
          fakeTurn(
            id: 'turn-1',
            status: ConversationTurnStatus.completed,
            userMessage: fakeUserMessage(id: 'user-turn-1', content: '问题 1'),
            activeAttemptId: 'a-1',
          ),
          fakeTurn(
            id: 'turn-2',
            ordinal: 1,
            status: ConversationTurnStatus.completed,
            userMessage: user2,
            activeAttemptId: 'a-2',
          ),
        ],
        messages: [
          fakeUserMessage(id: 'user-turn-1', content: '问题 1'),
          fakeAssistantMessage(id: 'assistant-a-1', content: '答案'),
          user2,
          assistant2,
        ],
      ),
    );
    await container
        .read(_chatTestProvider.notifier)
        .resume(sessionId: 'session-1');

    await notifier.regenerateMessage(firstAssistantId);
    await _flush();

    expect(repo.regenerateCalls, isEmpty);
    expect(container.read(_chatTestProvider).messages.length, 4);
  });

  test('没有用户消息时重新生成不调用仓储', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    expect(container.read(_chatTestProvider).messages, isEmpty);

    await notifier.regenerate();
    await _flush();

    expect(repo.regenerateCalls, isEmpty);
    expect(container.read(_chatTestProvider).messages, isEmpty);
  });

  test('completed event 更新 followUpQuestions', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    await _completeLatest(notifier, repo, quickActions: const ['再推荐', '换一批']);

    expect(container.read(_chatTestProvider).followUpQuestions, ['再推荐', '换一批']);
  });

  test('SSE failed event 保留请求 ID、路径和业务码诊断', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await _start(container);

    final pending = notifier.send('问题 1');
    await _flush();
    repo
      ..emit(acknowledged())
      ..emit(routed())
      ..emit(
        failed(
          message: '输入内容不合法',
          code: 'VALIDATION_ERROR',
          requestId: 'turn-request-id',
          path: '/api/v1/chat/sessions/session-1/turns',
        ),
      );
    await repo.closeActiveEvents();
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.activity, ChatActivity.turnFailed);
    expect(state.error?.diagnostics?.requestId, 'turn-request-id');
    expect(
      state.error?.diagnostics?.path,
      '/api/v1/chat/sessions/session-1/turns',
    );
    expect(state.error?.diagnostics?.backendCode, 'VALIDATION_ERROR');
    expect(
      state.error?.diagnostics?.exceptionType,
      'ConversationStreamException',
    );
    expect(state.messages.last.status, ChatMessageStatus.error);
  });
}
