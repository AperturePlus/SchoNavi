import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/features/chat/providers/chat_provider.dart';

import '../../helpers/fake_conversation_repository.dart';

final _chatTestProvider = chatProvider(Object());

const _recommendation = Recommendation(
  professorId: 'p_001',
  name: '张三',
  university: '南京大学',
  college: '计算机学院',
  title: '教授',
  researchFields: ['大模型'],
  matchLevel: MatchLevel.high,
  reason: '研究方向匹配。',
  limitations: ['以官网信息为准'],
);

ProviderContainer _containerWith(ControllableConversationRepository repo) {
  final container = ProviderContainer(
    overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(_chatTestProvider, (_, _) {});
  return container;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

ConversationAggregate _completedAggregate({
  String sessionId = 'session-1',
  String userText = '为什么推荐他',
  String answer = '测试回答',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 1,
}) {
  final session = fakeSession(id: sessionId, revision: revision);
  final user = fakeUserMessage(id: 'user-$turnId', content: userText);
  final assistant = fakeAssistantMessage(
    id: 'assistant-$attemptId',
    content: answer,
  );
  return fakeAggregate(
    session: session,
    turns: [
      fakeTurn(
        id: turnId,
        sessionId: sessionId,
        status: ConversationTurnStatus.completed,
        route: ConversationRoute.conversation,
        userMessage: user,
        activeAttemptId: attemptId,
      ),
    ],
    messages: [user, assistant],
  );
}

void main() {
  test('start 注入会话且不带助手问候', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(
        session: fakeSession(id: 's_1', professorId: 'p_001'),
      ),
    );
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);

    await container
        .read(_chatTestProvider.notifier)
        .start(sessionId: 's_1', professorId: 'p_001');
    final state = container.read(_chatTestProvider);

    expect(state.sessionId, 's_1');
    expect(state.professorId, 'p_001');
    expect(state.messages, isEmpty);
    expect(state.isResponding, isFalse);
  });

  test('send：事件增量进入 streaming，completed 后以聚合结果置 done', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('为什么推荐他');
    await _flush();
    repo
      ..emit(acknowledged())
      ..emit(routed())
      ..emit(delta(text: '测'))
      ..emit(delta(text: '试回答'));
    await _flush();

    var state = container.read(_chatTestProvider);
    expect(state.messages, hasLength(2));
    expect(state.messages.last.status, ChatMessageStatus.streaming);
    expect(state.messages.last.content, '测试回答');
    expect(state.activity, ChatActivity.streaming);

    final aggregate = _completedAggregate();
    repo.setAggregate(aggregate);
    repo.emit(completed(message: aggregate.messages.last, session: aggregate.session));
    await repo.closeActiveEvents();
    await pending;

    state = container.read(_chatTestProvider);
    expect(state.messages, hasLength(2));
    expect(state.messages.first.role, ChatRole.user);
    expect(state.messages.first.content, '为什么推荐他');
    expect(state.messages.last.role, ChatRole.assistant);
    expect(state.messages.last.status, ChatMessageStatus.done);
    expect(state.messages.last.content, '测试回答');
    expect(state.isResponding, isFalse);
    expect(repo.submitCalls.single.sessionId, 'session-1');
    expect(repo.submitCalls.single.text, '为什么推荐他');
  });

  test('send：completed 事件中的推荐卡片不会被 hydrate 空列表覆盖', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('给我推荐几个南开的做大模型的导师');
    await _flush();
    repo
      ..emit(acknowledged())
      ..emit(routed(route: ConversationRoute.recommendation));
    await _flush();

    final session = fakeSession(revision: 1);
    final user = fakeUserMessage(
      id: 'user-turn-1',
      content: '给我推荐几个南开的做大模型的导师',
    );
    final aggregateAssistant = fakeAssistantMessage(
      id: 'assistant-attempt-1',
      content: '已根据你的问题推荐了合适的导师。',
      kind: ChatMessageKind.recommendation,
    );
    repo.setAggregate(
      fakeAggregate(
        session: session,
        turns: [
          fakeTurn(
            status: ConversationTurnStatus.completed,
            route: ConversationRoute.recommendation,
            userMessage: user,
          ),
        ],
        messages: [user, aggregateAssistant],
      ),
    );
    repo.emit(
      completed(
        message: aggregateAssistant.copyWith(
          relatedRecommendations: const [_recommendation],
        ),
        session: session,
      ),
    );
    await repo.closeActiveEvents();
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.messages.last.relatedRecommendations, [_recommendation]);
    expect(state.messages.last.kind, ChatMessageKind.recommendation);
    expect(state.isResponding, isFalse);
  });

  test('send 失败：SSE error 保留 AppException 并生成错误消息', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('为什么推荐他');
    await _flush();
    repo
      ..emit(acknowledged())
      ..emit(routed())
      ..emit(failed(message: '服务异常，请稍后重试', code: 'SERVER_ERROR'));
    await repo.closeActiveEvents();
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.activity, ChatActivity.turnFailed);
    expect(state.error, isA<ValidationException>());
    expect(state.error?.diagnostics?.backendCode, 'SERVER_ERROR');
    expect(state.error?.diagnostics?.backendMessage, '服务异常，请稍后重试');
    expect(state.error?.diagnostics?.context['操作'], 'submitTurn');
    expect(state.error?.diagnostics?.context['活动轮次 ID'], 'turn-1');
    expect(state.error?.diagnostics?.context['活动尝试 ID'], 'attempt-1');
    expect(state.error?.diagnostics?.context['事件 revision 基线'], '0');
    expect(state.error?.diagnostics?.context['最近用户消息摘要'], '为什么推荐他');
    expect(state.messages.last.status, ChatMessageStatus.error);
    expect(state.messages.last.content, '服务异常，请稍后重试');
  });

  test('send stream 抛错：诊断详情携带安全聊天上下文', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('api_key=secret-token 为什么推荐他');
    await _flush();
    repo.activeEvents!.addError(const ValidationException('流式连接失败'));
    await repo.closeActiveEvents();
    await pending;

    final state = container.read(_chatTestProvider);
    final details = state.error?.diagnostics;
    expect(state.activity, ChatActivity.turnFailed);
    expect(state.error, isA<ValidationException>());
    expect(details?.requestId, repo.submitCalls.single.requestId);
    expect(details?.method, 'POST');
    expect(details?.context['操作'], 'submitTurn');
    expect(details?.context['请求 ID'], repo.submitCalls.single.requestId);
    expect(details?.context['会话 ID'], 'session-1');
    expect(details?.context['当前活动'], 'classifying');
    expect(details?.context['期望 revision'], '0');
    expect(details?.context['消息数'], '1');
    expect(
      details?.context['最近用户消息长度'],
      repo.submitCalls.single.text.length.toString(),
    );
    expect(details?.context['最近用户消息摘要'], contains('api_key=[REDACTED]'));
    expect(details?.context['最近用户消息摘要'], isNot(contains('secret-token')));
    expect(details?.context['提交文本摘要'], contains('api_key=[REDACTED]'));
    expect(details?.context['提交文本摘要'], isNot(contains('secret-token')));
  });

  test('流式中断时 hydrate 后保留已生成文本并附加错误原因', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('为什么推荐他');
    await _flush();
    repo
      ..emit(acknowledged())
      ..emit(routed())
      ..emit(delta(text: '已经生成的部分'));
    await _flush();

    final user = fakeUserMessage(content: '为什么推荐他');
    final partial = fakeAssistantMessage(
      id: 'assistant-attempt-1',
      content: '已经生成的部分',
      status: ChatMessageStatus.interrupted,
    );
    repo.setAggregate(
      fakeAggregate(
        session: fakeSession(revision: 1),
        turns: [
          fakeTurn(
            status: ConversationTurnStatus.interrupted,
            userMessage: user,
          ),
        ],
        messages: [user, partial],
      ),
    );
    repo.emit(failed(message: '生成中断：服务异常，请稍后重试'));
    await repo.closeActiveEvents();
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.messages.any((m) => m.content == '已经生成的部分'), isTrue);
    expect(state.messages.last.status, ChatMessageStatus.error);
    expect(state.messages.last.content, '生成中断：服务异常，请稍后重试');
  });

  test('stop：取消 attempt 并 hydrate 为中断态', () async {
    final repo = ControllableConversationRepository();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.send('为什么推荐他');
    await _flush();
    repo
      ..emit(acknowledged(attemptId: 'attempt-stop'))
      ..emit(routed(attemptId: 'attempt-stop'))
      ..emit(delta(attemptId: 'attempt-stop', text: '部分'));
    await _flush();

    expect(container.read(_chatTestProvider).isResponding, isTrue);
    expect(container.read(_chatTestProvider).messages.last.content, '部分');

    final user = fakeUserMessage(content: '为什么推荐他');
    final partial = fakeAssistantMessage(
      id: 'assistant-attempt-stop',
      content: '部分',
      status: ChatMessageStatus.interrupted,
    );
    repo.setAggregate(
      fakeAggregate(
        session: fakeSession(revision: 1),
        turns: [
          fakeTurn(
            status: ConversationTurnStatus.interrupted,
            userMessage: user,
            activeAttemptId: 'attempt-stop',
          ),
        ],
        messages: [user, partial],
      ),
    );

    await notifier.stop();
    await pending;

    final state = container.read(_chatTestProvider);
    expect(repo.cancelCalls, ['attempt-stop']);
    expect(state.isResponding, isFalse);
    expect(state.activity, ChatActivity.interrupted);
    expect(state.messages.last.status, ChatMessageStatus.interrupted);
    expect(state.messages.last.content, '部分');
  });

  test('regenerate 重发上一轮 turn', () async {
    final aggregate = _completedAggregate();
    final repo = ControllableConversationRepository(initialAggregate: aggregate);
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.resume(sessionId: 'session-1');

    final pending = notifier.regenerate();
    await _flush();
    repo
      ..emit(acknowledged(turnId: 'turn-1', attemptId: 'attempt-2', revision: 1))
      ..emit(routed(turnId: 'turn-1', attemptId: 'attempt-2', revision: 1))
      ..emit(
        delta(
          turnId: 'turn-1',
          attemptId: 'attempt-2',
          revision: 1,
          text: '新答案',
        ),
      );
    await _flush();

    final nextAggregate = _completedAggregate(
      answer: '新答案',
      attemptId: 'attempt-2',
      revision: 2,
    );
    repo.setAggregate(nextAggregate);
    repo.emit(
      completed(
        turnId: 'turn-1',
        attemptId: 'attempt-2',
        revision: 2,
        message: nextAggregate.messages.last,
        session: nextAggregate.session,
      ),
    );
    await repo.closeActiveEvents();
    await pending;

    expect(repo.regenerateCalls.single.turnId, 'turn-1');
    expect(
      container.read(_chatTestProvider).messages.map((m) => m.content),
      contains('新答案'),
    );
  });

  test('切换会话后旧流增量不能写入新会话', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: fakeAggregate(session: fakeSession(id: 'old')),
    );
    repo.setAggregate(fakeAggregate(session: fakeSession(id: 'new')));
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.start(sessionId: 'old');

    final pending = notifier.send('旧问题');
    await _flush();
    repo
      ..emit(acknowledged(sessionId: 'old'))
      ..emit(routed(sessionId: 'old'))
      ..emit(delta(sessionId: 'old', text: '旧增量'));
    await _flush();

    await notifier.start(sessionId: 'new');
    repo.emit(delta(sessionId: 'old', text: '迟到内容'));
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.sessionId, 'new');
    expect(
      state.messages.any((message) => message.content.contains('迟到内容')),
      isFalse,
    );
  });
}
