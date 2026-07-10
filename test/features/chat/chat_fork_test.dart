import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/fork_ref.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/features/chat/providers/chat_provider.dart';

import '../../helpers/fake_conversation_repository.dart';

final _chatProvider = chatProvider(Object());

const _professorId = 'p_001';

const _recommendation = Recommendation(
  professorId: _professorId,
  name: '张三',
  university: '清华大学',
  college: '计算机系',
  title: '教授',
  researchFields: ['计算机视觉'],
  matchLevel: MatchLevel.high,
  reason: '方向契合',
  limitations: [],
);

ProviderContainer _containerWith(ControllableConversationRepository repo) {
  final container = ProviderContainer(
    overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
  );
  container.listen(_chatProvider, (_, _) {});
  return container;
}

ConversationAggregate _sourceAggregate() {
  final session = fakeSession(id: 's1', revision: 1);
  final user = fakeUserMessage(id: 'u1', content: '想做 CV');
  final assistant = fakeAssistantMessage(
    id: 'a1',
    content: '为你挑了合适的导师',
    kind: ChatMessageKind.recommendation,
    relatedRecommendations: const [_recommendation],
  );
  return fakeAggregate(
    session: session,
    turns: [
      fakeTurn(
        id: 'turn-rec',
        sessionId: session.id,
        status: ConversationTurnStatus.completed,
        route: ConversationRoute.recommendation,
        userMessage: user,
        activeAttemptId: 'attempt-rec',
      ),
    ],
    messages: [user, assistant],
  );
}

ConversationAggregate _forkAggregate() {
  final source = _sourceAggregate();
  return fakeAggregate(
    session: fakeSession(
      id: 'fork-s1-p001',
      kind: ConversationSessionKind.fork,
      rootSessionId: 's1',
      sourceSessionId: 's1',
      sourceTurnId: 'turn-rec',
      professorId: _professorId,
      revision: 1,
    ),
    turns: source.turns,
    messages: source.messages,
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('startFork 通过来源推荐轮次创建 fork 并设置 anchor', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: _sourceAggregate(),
    );
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);

    final notifier = container.read(_chatProvider.notifier);
    await notifier.startFork(sourceSessionId: 's1', professorId: _professorId);
    final state = container.read(_chatProvider);

    expect(repo.forkCalls, 1);
    expect(state.sessionId, 'fork-s1-p_001');
    expect(state.forkAnchor, isNotNull);
    expect(state.forkAnchor!.mainSessionId, 's1');
    expect(state.forkAnchor!.professorId, _professorId);
    expect(state.messages, isNotEmpty);
  });

  test('fork 内后端路由为 forkReroute 时产出不可推荐卡消息', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: _forkAggregate(),
    );
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatProvider.notifier);
    await notifier.resume(sessionId: 'fork-s1-p001');

    final pending = notifier.send('换一批导师');
    await _flush();
    repo
      ..emit(acknowledged(sessionId: 'fork-s1-p001', revision: 1))
      ..emit(
        routed(
          sessionId: 'fork-s1-p001',
          revision: 1,
          route: ConversationRoute.forkReroute,
        ),
      );
    await _flush();

    final user = fakeUserMessage(id: 'u2', content: '换一批导师');
    final assistant = fakeAssistantMessage(
      id: 'a2',
      content: '请回到首页重新描述需求，我会为你重做推荐。',
      kind: ChatMessageKind.forkReroute,
    );
    repo.setAggregate(
      fakeAggregate(
        session: fakeSession(
          id: 'fork-s1-p001',
          kind: ConversationSessionKind.fork,
          rootSessionId: 's1',
          sourceSessionId: 's1',
          sourceTurnId: 'turn-rec',
          professorId: _professorId,
          revision: 2,
        ),
        turns: [
          ..._forkAggregate().turns,
          fakeTurn(
            id: 'turn-2',
            sessionId: 'fork-s1-p001',
            status: ConversationTurnStatus.completed,
            route: ConversationRoute.forkReroute,
            userMessage: user,
          ),
        ],
        messages: [..._forkAggregate().messages, user, assistant],
      ),
    );
    repo.emit(
      completed(
        sessionId: 'fork-s1-p001',
        revision: 2,
        message: assistant,
        session: repo.aggregates['fork-s1-p001']!.session,
      ),
    );
    await repo.closeActiveEvents();
    await pending;

    final reroute = container
        .read(_chatProvider)
        .messages
        .where((m) => m.kind == ChatMessageKind.forkReroute)
        .toList();
    expect(reroute, hasLength(1));
    expect(reroute.single.relatedRecommendations, isEmpty);
    expect(reroute.single.status, ChatMessageStatus.done);
  });

  test('resume(fork) 根据 fork session aggregate 重建 forkAnchor', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: _forkAggregate(),
    );
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);

    await container
        .read(_chatProvider.notifier)
        .resume(sessionId: 'fork-s1-p001', isFork: true, mainSessionId: 's1');
    final state = container.read(_chatProvider);

    expect(state.forkAnchor, isNotNull);
    expect(state.forkAnchor!.forkId, 'fork-s1-p001');
    expect(state.forkAnchor!.mainSessionId, 's1');
    expect(state.sessionId, 'fork-s1-p001');
  });

  test('copyWith 显式置 forkAnchor=null 可清空', () {
    final anchor = ForkRef(
      forkId: 'f1',
      mainSessionId: 's1',
      professorId: 'p1',
      professorName: '张三',
      university: '清华',
      college: '计算机系',
      createdAt: fakeNow,
    );
    final state = ChatState(
      sessionId: 's1',
      professorId: 'p1',
      messages: const [],
      activity: ChatActivity.idle,
      followUpQuestions: const [],
      forkAnchor: anchor,
    );

    expect(state.copyWith(forkAnchor: null).forkAnchor, isNull);
    expect(state.copyWith().forkAnchor, anchor);
  });

  test('startFork race guard discards stale state write', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: _sourceAggregate(),
    );
    repo.setAggregate(fakeAggregate(session: fakeSession(id: 'new-session')));
    final parkedSourceLoad = repo.parkNextLoad();
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);
    final notifier = container.read(_chatProvider.notifier);

    final forkFuture = notifier.startFork(
      sourceSessionId: 's1',
      professorId: _professorId,
    );
    await _flush();

    await notifier.start(sessionId: 'new-session', professorId: 'p2');
    parkedSourceLoad.complete(Success(_sourceAggregate()));
    await forkFuture;

    final state = container.read(_chatProvider);
    expect(repo.forkCalls, 0);
    expect(state.sessionId, 'new-session');
    expect(state.professorId, isNull);
    expect(state.forkAnchor, isNull);
  });

  test('startFork 来源不可用时进入 loadFailed 且不创建 fork', () async {
    final repo = ControllableConversationRepository(
      initialAggregate: _sourceAggregate(),
    )..loadResult = const Failure(NotFoundException());
    final container = _containerWith(repo);
    addTearDown(repo.dispose);
    addTearDown(container.dispose);

    await container
        .read(_chatProvider.notifier)
        .startFork(sourceSessionId: 's1', professorId: _professorId);
    final state = container.read(_chatProvider);

    expect(repo.forkCalls, 0);
    expect(state.sessionId, isNull);
    expect(state.forkAnchor, isNull);
    expect(state.activity, ChatActivity.loadFailed);
    expect(state.error, isA<NotFoundException>());
  });
}
