import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/ai/llm_client.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/local/local_conversation_repository.dart';
import 'package:scho_navi/data/local/memory_conversation_store.dart';
import 'package:scho_navi/data/mock/mock_db.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/domain/repositories/recommendation_repository.dart';
import 'package:scho_navi/features/chat/providers/chat_provider.dart';
import 'package:scho_navi/shared/utils/quick_actions_source.dart';
import 'package:scho_navi/shared/utils/recommendation_need_classifier.dart';

class _RecordingLlm implements LlmClient {
  _RecordingLlm(this.answer);

  final String answer;
  int streamCalls = 0;

  @override
  Future<Result<String>> complete({
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.7,
  }) async => const Success('摘要');

  @override
  Stream<String> stream({
    required List<LlmMessage> messages,
    double temperature = 0.7,
  }) async* {
    streamCalls++;
    yield answer;
  }
}

class _FakeRecRepo implements RecommendationRepository {
  _FakeRecRepo(this._result);

  final Result<RecommendationResult> _result;
  int calls = 0;
  String? lastPrompt;
  String? lastSessionId;

  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async {
    calls++;
    lastPrompt = prompt;
    lastSessionId = sessionId;
    return _result;
  }
}

class _CompleterRecRepo implements RecommendationRepository {
  final completer = Completer<Result<RecommendationResult>>();
  int calls = 0;

  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) {
    calls++;
    return completer.future;
  }
}

class _QueueRecRepo implements RecommendationRepository {
  _QueueRecRepo(this.results);

  final List<Result<RecommendationResult>> results;
  int calls = 0;

  @override
  Future<Result<RecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async => results[calls++];
}

class _FakeNeedClassifier implements RecommendationNeedClassifier {
  _FakeNeedClassifier(this._value);

  final bool _value;
  int calls = 0;

  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) async {
    calls++;
    return _value;
  }
}

class _BlockingNeedClassifier implements RecommendationNeedClassifier {
  final completer = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> needRecommendations(
    String followUp, {
    RecommendationResult? lastResult,
  }) {
    calls++;
    return completer.future;
  }
}

class _QuickActions implements QuickActionsSource {
  @override
  Future<Result<List<String>>> fetch({
    required String followUp,
    RecommendationResult? lastResult,
  }) async => const Success(['继续了解']);
}

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

class _FakeHistoryRepo implements HistoryRepository {
  @override
  List<SearchHistoryItem> list() => const [];
  @override
  Stream<List<SearchHistoryItem>> watch() => const Stream.empty();
  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async => null;
  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {}
  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {}
  @override
  Future<void> remove(String sessionId) async {}
  @override
  Future<void> clear() async {}
}

RecommendationResult _recResult({String sessionId = ''}) =>
    RecommendationResult(
      sessionId: sessionId,
      queryUnderstanding: const QueryUnderstanding(
        researchInterests: ['计算机视觉'],
        preferredLocations: ['北京'],
        preferredUniversities: [],
        degreeStage: null,
        uncertainties: [],
      ),
      recommendations: const [
        Recommendation(
          professorId: 'p_001',
          name: '张三',
          university: '清华大学',
          college: '计算机学院',
          title: '教授',
          researchFields: ['计算机视觉'],
          matchLevel: MatchLevel.high,
          reason: '方向契合',
          limitations: [],
        ),
        Recommendation(
          professorId: 'p_002',
          name: '李四',
          university: '北京大学',
          college: '信息科学技术学院',
          title: '副教授',
          researchFields: ['计算机视觉'],
          matchLevel: MatchLevel.medium,
          reason: '方向相关',
          limitations: [],
        ),
      ],
      followUpQuestions: const ['只看北京', '偏理论'],
    );

ProviderContainer _container({
  required ConversationRepository conversationRepo,
}) {
  final container = ProviderContainer(
    overrides: [
      conversationRepositoryProvider.overrideWithValue(conversationRepo),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
      historyRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
    ],
  );
  container.listen(_chatTestProvider, (_, _) {});
  return container;
}

LocalConversationRepository _conversationRepo({
  required MemoryConversationStore store,
  required LlmClient llm,
  required RecommendationRepository recRepo,
  required RecommendationNeedClassifier needClassifier,
}) {
  return LocalConversationRepository(
    store: store,
    llm: llm,
    recommendations: recRepo,
    classifier: needClassifier,
    quickActions: _QuickActions(),
    db: MockDb(),
    profile: () => const UserProfile(),
  );
}

final _chatTestProvider = chatProvider(Object());

void main() {
  test('bootstrapRecommendations：首轮产用户消息 + 助手消息含推荐卡片', () async {
    final store = MemoryConversationStore();
    final rec = _FakeRecRepo(Success(_recResult()));
    final llm = _RecordingLlm('可以');
    final repo = _conversationRepo(
      store: store,
      llm: llm,
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    await container.read(_chatTestProvider.notifier).create();
    final initialSession = container.read(_chatTestProvider).sessionId!;
    await container
        .read(_chatTestProvider.notifier)
        .bootstrapRecommendations('想做计算机视觉，想去北京');

    final state = container.read(_chatTestProvider);
    expect(state.sessionId, initialSession);
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, ChatRole.user);
    expect(state.messages[0].content, '想做计算机视觉，想去北京');
    expect(state.messages[1].role, ChatRole.assistant);
    expect(state.messages[1].status, ChatMessageStatus.done);
    expect(state.messages[1].kind, ChatMessageKind.recommendation);
    expect(state.messages[1].relatedRecommendations, hasLength(2));
    expect(state.messages[1].relatedRecommendations.first.name, '张三');
    expect(state.messages[1].content, contains('为你挑了'));
    expect(rec.calls, 1);
    expect(rec.lastSessionId, initialSession);
    expect(llm.streamCalls, 0);
    expect(state.followUpQuestions, ['只看北京', '偏理论']);
  });

  test('bootstrapRecommendations 守卫：busy 时重复提交被忽略', () async {
    final store = MemoryConversationStore();
    final rec = _CompleterRecRepo();
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    final pending = notifier.bootstrapRecommendations('第一次');
    await container.pump();

    expect(container.read(_chatTestProvider).activity, ChatActivity.classifying);
    await notifier.bootstrapRecommendations('第二次');
    await notifier.send('重复追问');

    rec.completer.complete(Success(_recResult()));
    await pending;
    expect(rec.calls, 1);
    final messages = container.read(_chatTestProvider).messages;
    expect(messages, hasLength(2));
    expect(messages.any((message) => message.content == '第二次'), isFalse);
    expect(messages.any((message) => message.content == '重复追问'), isFalse);
  });

  test('追问经 needClassifier 命中：新助手消息含推荐卡片', () async {
    final store = MemoryConversationStore();
    final need = _FakeNeedClassifier(true);
    final rec = _FakeRecRepo(Success(_recResult()));
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('好的'),
      recRepo: rec,
      needClassifier: need,
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    await notifier.send('只看上海的');

    final msgs = container.read(_chatTestProvider).messages;
    expect(msgs, hasLength(4));
    expect(msgs.last.role, ChatRole.assistant);
    expect(msgs.last.kind, ChatMessageKind.recommendation);
    expect(msgs.last.relatedRecommendations, hasLength(2));
    expect(need.calls, 1);
    expect(rec.calls, 2);
  });

  test('追问未命中：纯文字流式，无推荐卡片', () async {
    final store = MemoryConversationStore();
    final need = _FakeNeedClassifier(false);
    final rec = _FakeRecRepo(Success(_recResult()));
    final llm = _RecordingLlm('解释');
    final repo = _conversationRepo(
      store: store,
      llm: llm,
      recRepo: rec,
      needClassifier: need,
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    await notifier.send('为什么推荐他');

    final followupAssistant = container.read(_chatTestProvider).messages.last;
    expect(followupAssistant.role, ChatRole.assistant);
    expect(followupAssistant.kind, ChatMessageKind.conversation);
    expect(followupAssistant.content, '解释');
    expect(followupAssistant.relatedRecommendations, isEmpty);
    expect(rec.calls, 1);
    expect(llm.streamCalls, 1);
  });

  test('推荐获取失败：显示可重试的推荐错误，不调用聊天流', () async {
    final store = MemoryConversationStore();
    final rec = _FakeRecRepo(const Failure(ServerException()));
    final llm = _RecordingLlm('兜底回复');
    final repo = _conversationRepo(
      store: store,
      llm: llm,
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');

    final msgs = container.read(_chatTestProvider).messages;
    expect(msgs, hasLength(2));
    final assistant = msgs.last;
    expect(assistant.role, ChatRole.assistant);
    expect(assistant.status, ChatMessageStatus.error);
    expect(assistant.relatedRecommendations, isEmpty);
    expect(llm.streamCalls, 0);
  });

  test('regenerate 不重新调用推荐仓储（卡片沿用原结果）', () async {
    final store = MemoryConversationStore();
    final rec = _FakeRecRepo(Success(_recResult()));
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('再答'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    final recCallsBefore = rec.calls;

    await notifier.regenerate();

    expect(rec.calls, recCallsBefore);
  });

  test('分类未完成时重复发送只保留第一条用户消息', () async {
    final store = MemoryConversationStore();
    final need = _BlockingNeedClassifier();
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('解释'),
      recRepo: _FakeRecRepo(Success(_recResult())),
      needClassifier: need,
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create(professorId: 'p_001');
    final pending = notifier.send('第一条');
    await container.pump();
    await notifier.send('第二条');

    need.completer.complete(false);
    await pending;
    expect(need.calls, 1);
    final messages = container.read(_chatTestProvider).messages;
    expect(messages.where((message) => message.content == '第一条'), hasLength(1));
    expect(messages.any((message) => message.content == '第二条'), isFalse);
    expect(messages.last.content, '解释');
  });

  test('切换会话后旧推荐结果不能覆盖新会话', () async {
    final store = MemoryConversationStore();
    final rec = _CompleterRecRepo();
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    final oldSession = container.read(_chatTestProvider).sessionId!;
    final pending = notifier.bootstrapRecommendations('旧请求');
    await container.pump();

    await notifier.create();
    final newSession = container.read(_chatTestProvider).sessionId!;
    rec.completer.complete(Success(_recResult(sessionId: oldSession)));
    await pending;

    final state = container.read(_chatTestProvider);
    expect(state.sessionId, newSession);
    expect(state.messages, isEmpty);
  });

  test('推荐失败后可重试并成功产卡', () async {
    final store = MemoryConversationStore();
    final rec = _QueueRecRepo([
      const Failure(ServerException()),
      Success(_recResult()),
    ]);
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    final errorMessage = container.read(_chatTestProvider).messages.last;
    expect(errorMessage.status, ChatMessageStatus.error);

    await notifier.retryRecommendation(errorMessage.id);
    final state = container.read(_chatTestProvider);
    expect(rec.calls, 2);
    expect(state.messages.last.status, ChatMessageStatus.done);
    expect(state.messages.last.relatedRecommendations, isNotEmpty);
  });

  test('bootstrap 完成后占位替换为推荐结果', () async {
    final store = MemoryConversationStore();
    final rec = _CompleterRecRepo();
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(false),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    final pending = notifier.bootstrapRecommendations('想做CV');
    await container.pump();

    rec.completer.complete(Success(_recResult()));
    await pending;
    final done = container.read(_chatTestProvider).messages;
    expect(done, hasLength(2));
    expect(done[1].status, ChatMessageStatus.done);
    expect(done[1].relatedRecommendations, hasLength(2));
  });

  test('send 推荐命中：占位替换为结果，不追加第三条', () async {
    final store = MemoryConversationStore();
    final rec = _FakeRecRepo(Success(_recResult()));
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(true),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    await notifier.send('只看北京的');

    final msgs = container.read(_chatTestProvider).messages;
    expect(msgs, hasLength(4));
    expect(msgs.last.role, ChatRole.assistant);
    expect(msgs.last.status, ChatMessageStatus.done);
    expect(msgs.last.kind, ChatMessageKind.recommendation);
    expect(msgs.last.relatedRecommendations, hasLength(2));
  });

  test('send 推荐失败：占位替换为 error，不追加第三条', () async {
    final store = MemoryConversationStore();
    final rec = _QueueRecRepo([
      Success(_recResult()),
      const Failure(ServerException()),
    ]);
    final repo = _conversationRepo(
      store: store,
      llm: _RecordingLlm('x'),
      recRepo: rec,
      needClassifier: _FakeNeedClassifier(true),
    );
    final container = _container(conversationRepo: repo);
    addTearDown(container.dispose);

    final notifier = container.read(_chatTestProvider.notifier);
    await notifier.create();
    await notifier.bootstrapRecommendations('想做CV');
    await notifier.send('只看北京的');

    final msgs = container.read(_chatTestProvider).messages;
    expect(msgs, hasLength(4));
    expect(msgs.last.status, ChatMessageStatus.error);
  });

  test('新内存 store 会话不跨 provider/repository 实例恢复', () async {
    final firstStore = MemoryConversationStore();
    final first = _conversationRepo(
      store: firstStore,
      llm: _RecordingLlm('x'),
      recRepo: _FakeRecRepo(Success(_recResult())),
      needClassifier: _FakeNeedClassifier(false),
    );
    final firstContainer = _container(conversationRepo: first);
    addTearDown(firstContainer.dispose);

    final firstNotifier = firstContainer.read(_chatTestProvider.notifier);
    await firstNotifier.create();
    await firstNotifier.bootstrapRecommendations('想做CV');
    final oldSession = firstContainer.read(_chatTestProvider).sessionId!;

    final second = _conversationRepo(
      store: MemoryConversationStore(),
      llm: _RecordingLlm('x'),
      recRepo: _FakeRecRepo(Success(_recResult())),
      needClassifier: _FakeNeedClassifier(false),
    );
    final secondContainer = _container(conversationRepo: second);
    addTearDown(secondContainer.dispose);

    await secondContainer.read(_chatTestProvider.notifier).start(
          sessionId: oldSession,
        );

    expect(
      secondContainer.read(_chatTestProvider).activity,
      ChatActivity.loadFailed,
    );
  });
}
