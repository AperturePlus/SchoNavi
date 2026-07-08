import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/ai/llm_client.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/local/local_conversation_repository.dart';
import 'package:scho_navi/data/local/memory_conversation_store.dart';
import 'package:scho_navi/data/mock/mock_db.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/recommendation_repository.dart';
import 'package:scho_navi/shared/utils/quick_actions_source.dart';
import 'package:scho_navi/shared/utils/recommendation_need_classifier.dart';

class _RecordingLlm implements LlmClient {
  _RecordingLlm(this.answer);

  final String answer;
  final List<List<LlmMessage>> calls = [];

  @override
  Future<Result<String>> complete({
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
  }) async {
    calls.add(messages);
    return Success(answer);
  }

  @override
  Stream<String> stream({
    required List<LlmMessage> messages,
    double temperature = 0.7,
  }) async* {
    calls.add(messages);
    yield answer;
  }
}

class _RecommendationRepo implements RecommendationRepository {
  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async => Success(
    RecommendationResult(
      sessionId: sessionId ?? '',
      queryUnderstanding: const QueryUnderstanding(
        researchInterests: ['计算机视觉'],
        preferredLocations: [],
        preferredUniversities: [],
        uncertainties: [],
      ),
      recommendations: const [
        Recommendation(
          professorId: 'p_001',
          name: '张三',
          university: '测试大学',
          college: '计算机学院',
          title: '教授',
          researchFields: ['计算机视觉'],
          matchLevel: MatchLevel.high,
          reason: '方向匹配',
          limitations: [],
        ),
      ],
      followUpQuestions: const ['为什么推荐'],
    ),
  );
}

class _MutableRecommendationRepo implements RecommendationRepository {
  String reason = '旧来源理由';

  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async => Success(
    RecommendationResult(
      sessionId: sessionId ?? '',
      queryUnderstanding: const QueryUnderstanding(
        researchInterests: ['计算机视觉'],
        preferredLocations: [],
        preferredUniversities: [],
        uncertainties: [],
      ),
      recommendations: [
        Recommendation(
          professorId: 'p_001',
          name: '张三',
          university: '测试大学',
          college: '计算机学院',
          title: '教授',
          researchFields: const ['计算机视觉'],
          matchLevel: MatchLevel.high,
          reason: reason,
          limitations: const [],
        ),
      ],
      followUpQuestions: const ['为什么推荐'],
    ),
  );
}

class _Classifier implements RecommendationNeedClassifier {
  bool value = false;

  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) async => value;
}

class _FailOnceClassifier implements RecommendationNeedClassifier {
  bool failed = false;

  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) async {
    if (!failed) {
      failed = true;
      throw StateError('classifier failed');
    }
    return false;
  }
}

class _QuickActions implements QuickActionsSource {
  @override
  Future<Result<List<String>>> fetch({
    required String followUp,
    RecommendationResult? lastResult,
  }) async => const Success(['继续了解']);
}

LocalConversationRepository _repository(
  MemoryConversationStore store,
  LlmClient llm,
  _Classifier classifier, {
  RecommendationRepository? recommendations,
}) => LocalConversationRepository(
  store: store,
  llm: llm,
  recommendations: recommendations ?? _RecommendationRepo(),
  classifier: classifier,
  quickActions: _QuickActions(),
  db: MockDb(),
  profile: () => const UserProfile(),
);

void main() {
  late MemoryConversationStore store;
  late _Classifier classifier;

  setUp(() {
    store = MemoryConversationStore();
    classifier = _Classifier();
  });

  test('重建 repository 后从同一内存 store 恢复推荐与对话上下文', () async {
    final first = _repository(store, _RecordingLlm('unused'), classifier);
    final created = (await first.createSession() as Success).data;
    final firstEvents = await first
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    expect(firstEvents.whereType<ConversationCompleted>(), hasLength(1));

    final restartedLlm = _RecordingLlm('这是恢复后的回答');
    final restarted = _repository(store, restartedLlm, classifier);
    final secondEvents = await restarted
        .submitTurn(
          sessionId: created.id,
          text: '第一位导师为什么适合我',
          expectedRevision: 1,
        )
        .toList();

    expect(secondEvents.last, isA<ConversationCompleted>());
    final prompt = restartedLlm.calls.single.map((m) => m.content).join('\n');
    expect(prompt, contains('张三'));
    expect(prompt, contains('第一位导师为什么适合我'));
  });

  test('fork 按来源轮次和导师唯一，且不继承主会话后续尾部', () async {
    final llm = _RecordingLlm('回答');
    final repo = _repository(store, llm, classifier);
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final source = (await repo.loadSession(created.id) as Success).data;
    final sourceTurnId = source.turns.single.id;

    final concurrent = await Future.wait([
      repo.forkSessionAtTurn(
        sourceSessionId: created.id,
        sourceTurnId: sourceTurnId,
        professorId: 'p_001',
      ),
      repo.forkSessionAtTurn(
        sourceSessionId: created.id,
        sourceTurnId: sourceTurnId,
        professorId: 'p_001',
      ),
    ]);
    final firstFork = (concurrent.first as Success).data;
    final reused = (concurrent.last as Success).data;
    expect(reused.id, firstFork.id);

    final emptyFork = (await repo.loadSession(firstFork.id) as Success).data;
    expect(emptyFork.turns, isEmpty);
    expect(emptyFork.messages, isEmpty);

    await repo
        .submitTurn(sessionId: created.id, text: '继续问主会话', expectedRevision: 1)
        .toList();
    await repo
        .submitTurn(
          sessionId: firstFork.id,
          text: '张三为什么适合我',
          expectedRevision: 0,
        )
        .toList();
    final forkAggregate =
        (await repo.loadSession(firstFork.id) as Success).data;
    expect(forkAggregate.turns, hasLength(1));
    expect(forkAggregate.messages.map((message) => message.content), [
      '张三为什么适合我',
      '回答',
    ]);
    expect(forkAggregate.messages.any((m) => m.content == '继续问主会话'), isFalse);
    final forkPrompt = llm.calls.last
        .map((message) => message.content)
        .join('\n');
    expect(forkPrompt, contains('推荐计算机视觉导师'));
    expect(forkPrompt, contains('张三'));
    expect(forkPrompt, contains('张三为什么适合我'));
    expect(forkPrompt, isNot(contains('继续问主会话')));

    classifier.value = true;
    await repo
        .submitTurn(sessionId: created.id, text: '换一批导师', expectedRevision: 2)
        .toList();
    final updated = (await repo.loadSession(created.id) as Success).data;
    final secondFork =
        (await repo.forkSessionAtTurn(
                  sourceSessionId: created.id,
                  sourceTurnId: updated.turns.last.id,
                  professorId: 'p_001',
                )
                as Success)
            .data;
    expect(secondFork.id, isNot(firstFork.id));
  });

  test('fork 源上下文按创建时 active attempt 冻结', () async {
    final recommendations = _MutableRecommendationRepo();
    final llm = _RecordingLlm('fork 回答');
    final repo = _repository(
      store,
      llm,
      classifier,
      recommendations: recommendations,
    );
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final source = (await repo.loadSession(created.id) as Success).data;
    final sourceTurnId = source.turns.single.id;
    final firstFork =
        (await repo.forkSessionAtTurn(
                  sourceSessionId: created.id,
                  sourceTurnId: sourceTurnId,
                  professorId: 'p_001',
                )
                as Success)
            .data;

    recommendations.reason = '新来源理由';
    await repo
        .regenerateTurn(
          sessionId: created.id,
          turnId: sourceTurnId,
          expectedRevision: 1,
        )
        .toList();
    final secondFork =
        (await repo.forkSessionAtTurn(
                  sourceSessionId: created.id,
                  sourceTurnId: sourceTurnId,
                  professorId: 'p_001',
                )
                as Success)
            .data;
    expect(secondFork.id, isNot(firstFork.id));

    await repo
        .submitTurn(
          sessionId: firstFork.id,
          text: '旧 fork 追问',
          expectedRevision: 0,
        )
        .toList();
    final oldForkPrompt = llm.calls.last
        .map((message) => message.content)
        .join('\n');
    expect(oldForkPrompt, contains('旧来源理由'));
    expect(oldForkPrompt, isNot(contains('新来源理由')));

    await repo
        .submitTurn(
          sessionId: secondFork.id,
          text: '新 fork 追问',
          expectedRevision: 0,
        )
        .toList();
    final newForkPrompt = llm.calls.last
        .map((message) => message.content)
        .join('\n');
    expect(newForkPrompt, contains('新来源理由'));
    expect(newForkPrompt, isNot(contains('旧来源理由')));
  });

  test('删除主会话级联删除 fork', () async {
    final repo = _repository(store, _RecordingLlm('回答'), classifier);
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final aggregate = (await repo.loadSession(created.id) as Success).data;
    final fork =
        (await repo.forkSessionAtTurn(
                  sourceSessionId: created.id,
                  sourceTurnId: aggregate.turns.single.id,
                  professorId: 'p_001',
                )
                as Success)
            .data;

    expect(await repo.deleteSession(created.id), isA<Success<void>>());
    expect(await repo.loadSession(created.id), isA<Failure>());
    expect(await repo.loadSession(fork.id), isA<Failure>());
  });

  test('清空会话删除全部主会话和 fork', () async {
    final repo = _repository(store, _RecordingLlm('回答'), classifier);
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final aggregate = (await repo.loadSession(created.id) as Success).data;
    final fork =
        (await repo.forkSessionAtTurn(
                  sourceSessionId: created.id,
                  sourceTurnId: aggregate.turns.single.id,
                  professorId: 'p_001',
                )
                as Success)
            .data;

    expect((await repo.listSessions() as Success).data, isNotEmpty);
    expect((await repo.listForks(created.id) as Success).data, isNotEmpty);

    expect(await repo.clearSessions(), isA<Success<void>>());

    expect((await repo.listSessions() as Success).data, isEmpty);
    expect((await repo.listForks(created.id) as Success).data, isEmpty);
    expect(await repo.loadSession(created.id), isA<Failure>());
    expect(await repo.loadSession(fork.id), isA<Failure>());
  });

  test('助手反馈保存到内存 store 并在 repository 重建后恢复', () async {
    final repo = _repository(store, _RecordingLlm('回答'), classifier);
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final aggregate = (await repo.loadSession(created.id) as Success).data;
    final assistant = aggregate.messages.last;

    expect(
      await repo.setMessageFeedback(assistant.id, ChatMessageFeedback.like),
      isA<Success<void>>(),
    );
    final restarted = _repository(store, _RecordingLlm('回答'), classifier);
    final reloaded = (await restarted.loadSession(created.id) as Success).data;
    expect(reloaded.messages.last.feedback, ChatMessageFeedback.like);
  });

  test('分类失败重试复用同一 turn，不重复用户消息', () async {
    final failOnce = _FailOnceClassifier();
    final repo = LocalConversationRepository(
      store: store,
      llm: _RecordingLlm('重试成功'),
      recommendations: _RecommendationRepo(),
      classifier: failOnce,
      quickActions: _QuickActions(),
      db: MockDb(),
      profile: () => const UserProfile(),
    );
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    final failedEvents = await repo
        .submitTurn(sessionId: created.id, text: '为什么适合我', expectedRevision: 1)
        .toList();
    expect(failedEvents.last, isA<ConversationFailed>());
    final failed = (await repo.loadSession(created.id) as Success).data;
    expect(failed.session.revision, 2);
    expect(failed.turns.last.status, ConversationTurnStatus.failed);

    final retried = await repo
        .regenerateTurn(
          sessionId: created.id,
          turnId: failed.turns.last.id,
          expectedRevision: 2,
        )
        .toList();
    expect(retried.last, isA<ConversationCompleted>());
    final restored = (await repo.loadSession(created.id) as Success).data;
    expect(
      restored.messages.where((message) => message.role == ChatRole.user),
      hasLength(2),
    );
    expect(restored.messages.last.content, '重试成功');
  });

  test('部分流取消持久化为 interrupted，重新生成不重复用户消息', () async {
    final repo = _repository(store, _RecordingLlm('未使用'), classifier);
    final created = (await repo.createSession() as Success).data;
    await repo
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();

    final active = await store.beginTurn(
      sessionId: created.id,
      text: '继续解释',
      expectedRevision: 1,
    );
    await store.setTurnPhase(
      active.turn.id,
      ConversationTurnStatus.streaming,
      route: ConversationRoute.conversation,
    );
    await store.interruptAttempt(active.attempt.id, partial: '已经生成的部分');

    final interrupted = (await repo.loadSession(created.id) as Success).data;
    expect(interrupted.session.revision, 2);
    expect(interrupted.turns.last.status, ConversationTurnStatus.interrupted);
    expect(interrupted.messages.last.status, ChatMessageStatus.interrupted);
    expect(interrupted.messages.last.content, '已经生成的部分');

    final restarted = _repository(store, _RecordingLlm('重新生成完成'), classifier);
    await restarted
        .regenerateTurn(
          sessionId: created.id,
          turnId: interrupted.turns.last.id,
          expectedRevision: 2,
        )
        .toList();
    final completed = (await restarted.loadSession(created.id) as Success).data;
    expect(
      completed.messages.where((message) => message.role == ChatRole.user),
      hasLength(2),
    );
    expect(completed.messages.last.content, '重新生成完成');
  });

  test('同一 turn 多次重新生成后只投影最新 assistant', () async {
    final first = _repository(store, _RecordingLlm('初次回答'), classifier);
    final created = (await first.createSession() as Success).data;
    await first
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();
    await first
        .submitTurn(
          sessionId: created.id,
          text: '张三为什么适合我',
          expectedRevision: 1,
        )
        .toList();

    final afterFirst = (await first.loadSession(created.id) as Success).data;
    final turnId = afterFirst.turns.last.id;
    await _repository(store, _RecordingLlm('第二次回答'), classifier)
        .regenerateTurn(
          sessionId: created.id,
          turnId: turnId,
          expectedRevision: 2,
        )
        .toList();
    await _repository(store, _RecordingLlm('第三次回答'), classifier)
        .regenerateTurn(
          sessionId: created.id,
          turnId: turnId,
          expectedRevision: 3,
        )
        .toList();

    final completed = (await first.loadSession(created.id) as Success).data;
    expect(
      completed.messages
          .where((message) => message.content == '张三为什么适合我'),
      hasLength(1),
    );
    expect(completed.messages.last.content, '第三次回答');
    expect(
      completed.messages.any((message) => message.content == '初次回答'),
      isFalse,
    );
    expect(
      completed.messages.any((message) => message.content == '第二次回答'),
      isFalse,
    );
  });

  test('超过预算生成 checkpoint，并按摘要、推荐快照、近期轮次排序', () async {
    final session = await store.createSession();
    final recommendation = const Recommendation(
      professorId: 'p_001',
      name: '张三',
      university: '测试大学',
      college: '计算机学院',
      title: '教授',
      researchFields: ['计算机视觉'],
      matchLevel: MatchLevel.high,
      reason: '方向匹配',
      limitations: [],
    );
    final legacy = <ChatMessage>[];
    final userPadding = List.filled(900, '甲').join();
    final assistantPadding = List.filled(900, '乙').join();
    for (var index = 0; index < 10; index++) {
      legacy
        ..add(
          ChatMessage(
            id: 'old-user-$index',
            role: ChatRole.user,
            content: '第$index轮约束$userPadding',
            createdAt: DateTime.utc(2026, 6, 27, 0, index),
            relatedRecommendations: const [],
            status: ChatMessageStatus.done,
          ),
        )
        ..add(
          ChatMessage(
            id: 'old-assistant-$index',
            role: ChatRole.assistant,
            content: '第$index轮回答$assistantPadding',
            createdAt: DateTime.utc(2026, 6, 27, 0, index, 1),
            relatedRecommendations: index == 0 ? [recommendation] : const [],
            status: ChatMessageStatus.done,
            kind: index == 0
                ? ChatMessageKind.recommendation
                : ChatMessageKind.conversation,
          ),
        );
    }
    await store.importLegacyMessages(session.id, legacy);
    final llm = _RecordingLlm('压缩摘要');
    final repo = _repository(store, llm, classifier);

    await repo
        .submitTurn(
          sessionId: session.id,
          text: '预算后的新问题',
          expectedRevision: 10,
        )
        .toList();

    expect(llm.calls, hasLength(2));
    final context = llm.calls.last;
    expect(context[0].content, contains('SchoNavi'));
    expect(context[1].content, startsWith('【较早对话摘要】'));
    expect(context[2].content, startsWith('【最近推荐快照】'));
    expect(context[2].content, contains('张三'));
    expect(context.last.content, '预算后的新问题');
    expect(await store.latestCheckpoint(session.id), isNotNull);
  });

  test('新内存 store 不恢复上一实例的会话', () async {
    final firstStore = MemoryConversationStore();
    final first = _repository(firstStore, _RecordingLlm('回答'), classifier);
    final created = (await first.createSession() as Success).data;
    await first
        .submitTurn(
          sessionId: created.id,
          text: '推荐计算机视觉导师',
          expectedRevision: 0,
        )
        .toList();

    final secondStore = MemoryConversationStore();
    final second = _repository(secondStore, _RecordingLlm('回答'), classifier);

    expect(await second.loadSession(created.id), isA<Failure>());
    final sessions = (await second.listSessions() as Success).data;
    expect(sessions, isEmpty);
  });
}
