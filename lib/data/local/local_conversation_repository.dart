import 'dart:async';

import '../../core/ai/llm_client.dart';
import '../../core/error/app_exception.dart';
import '../../core/ids/uuid_v7.dart';
import '../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_aggregate.dart';
import '../../domain/entities/conversation_event.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/conversation_turn.dart';
import '../../domain/entities/query_understanding.dart';
import '../../domain/entities/recommendation_result.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../../shared/utils/quick_actions_source.dart';
import '../../shared/utils/recommendation_need_classifier.dart';
import '../mock/mock_db.dart';
import 'conversation_store.dart';

class LocalConversationRepository implements ConversationRepository {
  LocalConversationRepository({
    required this.store,
    required this.llm,
    required this.recommendations,
    required this.classifier,
    required this.quickActions,
    required this.db,
    required this.profile,
    this.initialize,
    UuidV7? ids,
  }) : ids = ids ?? store.ids;

  final ConversationStore store;
  final LlmClient llm;
  final RecommendationRepository recommendations;
  final RecommendationNeedClassifier classifier;
  final QuickActionsSource quickActions;
  final MockDb db;
  final UserProfile Function() profile;
  final Future<void> Function()? initialize;
  final UuidV7 ids;

  final Map<String, StringBuffer> _activeBuffers = {};

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async {
    try {
      await _ready();
      return Success(await store.createSession(professorId: professorId));
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async {
    try {
      await _ready();
      final aggregate = await store.loadAggregate(sessionId);
      if (aggregate == null) return const Failure(NotFoundException());
      return Success(aggregate);
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async {
    try {
      await _ready();
      return Success(
        await store.forkAtTurn(
          sourceSessionId: sourceSessionId,
          sourceTurnId: sourceTurnId,
          professorId: professorId,
        ),
      );
    } on StateError catch (error) {
      return Failure(ValidationException(error.message));
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) async* {
    await _ready();
    final normalized = text.trim();
    if (normalized.isEmpty) {
      throw const ValidationException('消息不能为空');
    }
    final started = await store.beginTurn(
      sessionId: sessionId,
      text: normalized,
      expectedRevision: expectedRevision,
      requestId: requestId,
    );
    final turn = started.turn;
    final attempt = started.attempt;
    final buffer = StringBuffer();
    _activeBuffers[attempt.id] = buffer;
    var finished = false;

    yield ConversationAcknowledged(
      sessionId: sessionId,
      turnId: turn.id,
      attemptId: attempt.id,
      revision: expectedRevision,
    );

    try {
      await store.setTurnPhase(turn.id, ConversationTurnStatus.classifying);
      final aggregate = await store.loadAggregate(
        sessionId,
        includeInherited: true,
      );
      if (aggregate == null) throw const NotFoundException();
      final lastResult = _lastRecommendation(aggregate);
      final needsRecommendation = await _needsRecommendation(
        aggregate,
        normalized,
      );

      if (needsRecommendation && aggregate.session.isFork) {
        yield* _completeForkReroute(
          aggregate.session,
          turn,
          attempt,
          expectedRevision,
        );
        finished = true;
        return;
      }
      if (needsRecommendation) {
        yield* _completeRecommendation(
          aggregate.session,
          turn,
          attempt,
          normalized,
          expectedRevision,
        );
        finished = true;
        return;
      }

      await store.setTurnPhase(
        turn.id,
        ConversationTurnStatus.connecting,
        route: ConversationRoute.conversation,
      );
      yield ConversationRouted(
        sessionId: sessionId,
        turnId: turn.id,
        attemptId: attempt.id,
        revision: expectedRevision,
        route: ConversationRoute.conversation,
      );
      final context = await _buildContext(aggregate.session.id);
      var sawDelta = false;
      await for (final delta in llm.stream(messages: context)) {
        if (!sawDelta) {
          sawDelta = true;
          await store.setTurnPhase(
            turn.id,
            ConversationTurnStatus.streaming,
            route: ConversationRoute.conversation,
          );
        }
        buffer.write(delta);
        yield ConversationDelta(
          sessionId: sessionId,
          turnId: turn.id,
          attemptId: attempt.id,
          revision: expectedRevision,
          text: delta,
        );
      }
      final message = ChatMessage(
        id: ids.generate(),
        role: ChatRole.assistant,
        content: buffer.toString(),
        createdAt: DateTime.now(),
        relatedRecommendations: const [],
        status: ChatMessageStatus.done,
      );
      final stored = await store.completeAttempt(
        sessionId: sessionId,
        turnId: turn.id,
        attemptId: attempt.id,
        message: message,
      );
      final updated = (await store.getSession(sessionId))!;
      finished = true;
      yield ConversationCompleted(
        sessionId: sessionId,
        turnId: turn.id,
        attemptId: attempt.id,
        revision: updated.revision,
        message: stored,
        session: updated,
        quickActions: await _quickActions(normalized, lastResult),
      );
    } catch (error) {
      await store.failAttempt(
        turnId: turn.id,
        attemptId: attempt.id,
        errorCode: error.runtimeType.toString(),
      );
      finished = true;
      final message = error is AppException
          ? error.message
          : error is StateError
          ? error.message
          : const UnknownException().message;
      final failedSession = await store.getSession(sessionId);
      yield ConversationFailed(
        sessionId: sessionId,
        turnId: turn.id,
        attemptId: attempt.id,
        revision: failedSession?.revision ?? expectedRevision + 1,
        message: message,
      );
    } finally {
      _activeBuffers.remove(attempt.id);
      if (!finished) {
        await store.interruptAttempt(attempt.id, partial: buffer.toString());
      }
    }
  }

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) async* {
    await _ready();
    final aggregate = await store.loadAggregate(sessionId);
    if (aggregate == null) throw const NotFoundException();
    final turn = aggregate.turns.where((t) => t.id == turnId).firstOrNull;
    if (turn == null) throw const NotFoundException();
    final attempt = await store.beginRegeneration(
      sessionId: sessionId,
      turnId: turnId,
      expectedRevision: expectedRevision,
      requestId: requestId,
    );
    final buffer = StringBuffer();
    _activeBuffers[attempt.id] = buffer;
    var finished = false;
    yield ConversationAcknowledged(
      sessionId: sessionId,
      turnId: turnId,
      attemptId: attempt.id,
      revision: expectedRevision,
    );
    try {
      if (turn.route == null) {
        await store.setTurnPhase(turn.id, ConversationTurnStatus.classifying);
        final current = await store.loadAggregate(
          sessionId,
          includeInherited: true,
        );
        if (current == null) throw const NotFoundException();
        final needsRecommendation = await _needsRecommendation(
          current,
          turn.userMessage.content,
        );
        if (needsRecommendation && current.session.isFork) {
          yield* _completeForkReroute(
            current.session,
            turn,
            attempt,
            expectedRevision,
          );
          finished = true;
          return;
        }
        if (needsRecommendation) {
          yield* _completeRecommendation(
            current.session,
            turn,
            attempt,
            turn.userMessage.content,
            expectedRevision,
          );
          finished = true;
          return;
        }
      }
      if (turn.route == ConversationRoute.recommendation) {
        yield* _completeRecommendation(
          aggregate.session,
          turn,
          attempt,
          turn.userMessage.content,
          expectedRevision,
        );
        finished = true;
        return;
      }
      if (turn.route == ConversationRoute.forkReroute) {
        yield* _completeForkReroute(
          aggregate.session,
          turn,
          attempt,
          expectedRevision,
        );
        finished = true;
        return;
      }
      yield ConversationRouted(
        sessionId: sessionId,
        turnId: turnId,
        attemptId: attempt.id,
        revision: expectedRevision,
        route: turn.route ?? ConversationRoute.conversation,
      );
      final context = await _buildContext(
        sessionId,
        excludeLastAssistant: true,
      );
      await for (final delta in llm.stream(messages: context)) {
        buffer.write(delta);
        yield ConversationDelta(
          sessionId: sessionId,
          turnId: turnId,
          attemptId: attempt.id,
          revision: expectedRevision,
          text: delta,
        );
      }
      final stored = await store.completeAttempt(
        sessionId: sessionId,
        turnId: turnId,
        attemptId: attempt.id,
        message: ChatMessage(
          id: ids.generate(),
          role: ChatRole.assistant,
          content: buffer.toString(),
          createdAt: DateTime.now(),
          relatedRecommendations: const [],
          status: ChatMessageStatus.done,
        ),
      );
      final updated = (await store.getSession(sessionId))!;
      finished = true;
      yield ConversationCompleted(
        sessionId: sessionId,
        turnId: turnId,
        attemptId: attempt.id,
        revision: updated.revision,
        message: stored,
        session: updated,
      );
    } catch (error) {
      await store.failAttempt(
        turnId: turnId,
        attemptId: attempt.id,
        errorCode: error.runtimeType.toString(),
      );
      finished = true;
      final failedSession = await store.getSession(sessionId);
      yield ConversationFailed(
        sessionId: sessionId,
        turnId: turnId,
        attemptId: attempt.id,
        revision: failedSession?.revision ?? expectedRevision + 1,
        message: error is AppException
            ? error.message
            : const UnknownException().message,
      );
    } finally {
      _activeBuffers.remove(attempt.id);
      if (!finished) {
        await store.interruptAttempt(attempt.id, partial: buffer.toString());
      }
    }
  }

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async {
    try {
      await _ready();
      await store.interruptAttempt(
        attemptId,
        partial: _activeBuffers[attemptId]?.toString() ?? '',
      );
      return const Success(null);
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async {
    try {
      await _ready();
      await store.setFeedback(messageId, feedback);
      return const Success(null);
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<List<ConversationSession>>> listSessions() async {
    try {
      await _ready();
      return Success(await store.listSessions());
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async {
    try {
      await _ready();
      return Success(await store.listForks(rootSessionId));
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    try {
      await _ready();
      await store.deleteSession(sessionId);
      return const Success(null);
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  @override
  Future<Result<void>> clearSessions() async {
    try {
      await _ready();
      await store.clearSessions();
      return const Success(null);
    } catch (_) {
      return const Failure(UnknownException());
    }
  }

  Stream<ConversationEvent> _completeForkReroute(
    ConversationSession session,
    ConversationTurn turn,
    AssistantAttempt attempt,
    int revision,
  ) async* {
    await store.setTurnPhase(
      turn.id,
      ConversationTurnStatus.connecting,
      route: ConversationRoute.forkReroute,
    );
    yield ConversationRouted(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      revision: revision,
      route: ConversationRoute.forkReroute,
    );
    final professor = session.professorId == null
        ? null
        : db.getProfessor(session.professorId!);
    final stored = await store.completeAttempt(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      message: ChatMessage(
        id: ids.generate(),
        role: ChatRole.assistant,
        content: '这里专注聊${professor?.name ?? '这位导师'}。想看新的导师推荐，请回首页开启新会话。',
        createdAt: DateTime.now(),
        relatedRecommendations: const [],
        status: ChatMessageStatus.done,
        kind: ChatMessageKind.forkReroute,
      ),
    );
    final updated = (await store.getSession(session.id))!;
    yield ConversationCompleted(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      revision: updated.revision,
      message: stored,
      session: updated,
    );
  }

  Stream<ConversationEvent> _completeRecommendation(
    ConversationSession session,
    ConversationTurn turn,
    AssistantAttempt attempt,
    String prompt,
    int revision,
  ) async* {
    await store.setTurnPhase(
      turn.id,
      ConversationTurnStatus.recommending,
      route: ConversationRoute.recommendation,
    );
    yield ConversationRouted(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      revision: revision,
      route: ConversationRoute.recommendation,
    );
    final result = await recommendations.getRecommendations(
      prompt: prompt,
      profile: profile(),
      sessionId: session.id,
    );
    if (result is Failure<RecommendationResult>) throw result.error;
    final data = (result as Success<RecommendationResult>).data;
    if (data.sessionId.isNotEmpty && data.sessionId != session.id) {
      throw const ValidationException('服务端返回了不匹配的会话 ID');
    }
    final stored = await store.completeAttempt(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      message: ChatMessage(
        id: ids.generate(),
        role: ChatRole.assistant,
        content: _openingLine(data),
        createdAt: DateTime.now(),
        relatedRecommendations: data.recommendations,
        status: ChatMessageStatus.done,
        kind: ChatMessageKind.recommendation,
      ),
    );
    final updated = (await store.getSession(session.id))!;
    yield ConversationCompleted(
      sessionId: session.id,
      turnId: turn.id,
      attemptId: attempt.id,
      revision: updated.revision,
      message: stored,
      session: updated,
      quickActions: data.followUpQuestions,
    );
  }

  Future<List<LlmMessage>> _buildContext(
    String sessionId, {
    bool excludeLastAssistant = false,
  }) async {
    final aggregate = await store.loadAggregate(
      sessionId,
      includeInherited: true,
    );
    if (aggregate == null) throw const NotFoundException();
    var visible = aggregate.messages
        .where((m) => m.status == ChatMessageStatus.done)
        .toList(growable: false);
    if (excludeLastAssistant &&
        visible.isNotEmpty &&
        visible.last.role == ChatRole.assistant) {
      visible = visible.sublist(0, visible.length - 1);
    }

    final totalChars = visible.fold<int>(0, (sum, m) => sum + m.content.length);
    var checkpoint = await store.latestCheckpoint(sessionId);
    if (checkpoint != null &&
        !aggregate.turns.any((turn) => turn.id == checkpoint!.throughTurnId)) {
      checkpoint = null;
    }
    var recent = _messagesAfterCheckpoint(
      visible,
      aggregate.turns,
      checkpoint?.throughTurnId,
    );
    final uncheckpointedChars = recent.fold<int>(
      0,
      (sum, message) => sum + _contextContent(message).length,
    );
    final needsCheckpoint =
        totalChars > 14400 &&
        aggregate.turns.length > 1 &&
        (checkpoint == null || uncheckpointedChars > 14400);
    if (needsCheckpoint) {
      final cutoffIndex = (aggregate.turns.length - 9).clamp(
        0,
        aggregate.turns.length - 2,
      );
      final nextUserId = aggregate.turns[cutoffIndex + 1].userMessage.id;
      final nextMessageIndex = visible.indexWhere(
        (message) => message.id == nextUserId,
      );
      final old = nextMessageIndex <= 0
          ? visible.take(1).toList(growable: false)
          : visible.take(nextMessageIndex).toList(growable: false);
      final summary = await _summarize(old);
      if (summary == null) {
        if (uncheckpointedChars > 19200 ||
            (checkpoint == null && totalChars > 19200)) {
          throw const ValidationException('历史上下文过长且摘要失败，请重试后再发送');
        }
      } else {
        final throughTurn = aggregate.turns[cutoffIndex];
        await store.saveCheckpoint(
          sessionId: sessionId,
          throughTurnId: throughTurn.id,
          summary: summary,
          modelVersion: 'local-v1',
        );
        checkpoint = await store.latestCheckpoint(sessionId);
        recent = _messagesAfterCheckpoint(
          visible,
          aggregate.turns,
          checkpoint?.throughTurnId,
        );
      }
    }
    ChatMessage? latestRecommendation;
    for (final message in visible.reversed) {
      if (message.kind == ChatMessageKind.recommendation &&
          message.relatedRecommendations.isNotEmpty) {
        latestRecommendation = message;
        break;
      }
    }
    return [
      LlmMessage('system', _systemPrompt(aggregate.session)),
      if (checkpoint != null)
        LlmMessage('system', '【较早对话摘要】\n${checkpoint.summary}'),
      if (checkpoint != null &&
          latestRecommendation != null &&
          !recent.any((message) => message.id == latestRecommendation!.id))
        LlmMessage(
          'system',
          '【最近推荐快照】\n${_contextContent(latestRecommendation)}',
        ),
      for (final message in recent)
        LlmMessage(
          message.role == ChatRole.user ? 'user' : 'assistant',
          _contextContent(message),
        ),
    ];
  }

  String _contextContent(ChatMessage message) {
    if (message.kind != ChatMessageKind.recommendation ||
        message.relatedRecommendations.isEmpty) {
      return message.content;
    }
    final lines = [message.content, '【本轮推荐结果】'];
    for (final r in message.relatedRecommendations) {
      lines.add(
        '- ${r.name}（${r.university} ${r.college}；'
        '方向：${r.researchFields.join('、')}）：${r.reason}',
      );
    }
    return lines.join('\n');
  }

  List<ChatMessage> _messagesAfterCheckpoint(
    List<ChatMessage> visible,
    List<ConversationTurn> turns,
    String? throughTurnId,
  ) {
    if (throughTurnId == null) return visible;
    final checkpointIndex = turns.indexWhere(
      (turn) => turn.id == throughTurnId,
    );
    if (checkpointIndex < 0) return visible;
    final nextTurnIndex = checkpointIndex + 1;
    if (nextTurnIndex >= turns.length) return const [];
    final nextUserId = turns[nextTurnIndex].userMessage.id;
    final messageIndex = visible.indexWhere(
      (message) => message.id == nextUserId,
    );
    return messageIndex < 0 ? visible : visible.sublist(messageIndex);
  }

  Future<String?> _summarize(List<ChatMessage> messages) async {
    final transcript = messages
        .map((message) => '${message.role.name}：${_contextContent(message)}')
        .join('\n');
    final result = await llm.complete(
      messages: [
        const LlmMessage(
          'system',
          '将导师咨询历史压缩成不超过 6000 字的结构化检查点。必须保留全部用户约束、'
              '导师名称与学校、已推荐结果、否定条件、未解决问题和已确认事实；不得新增事实。',
        ),
        LlmMessage('user', transcript),
      ],
      temperature: 0.1,
    );
    if (result is! Success<String>) return null;
    final summary = result.data.trim();
    if (summary.isEmpty || summary.length > 6000) return null;
    return summary;
  }

  String _systemPrompt(ConversationSession session) {
    const base =
        '你是 SchoNavi 的导师咨询助手。必须依据已保存的推荐结果和对话历史回答；'
        '不确定的事实要明确说明，不得编造联系方式、招生名额或录取结论。使用简洁中文。';
    final professor = session.professorId == null
        ? null
        : db.getProfessor(session.professorId!);
    if (professor == null) return base;
    return '$base\n【当前导师】${professor.name}（${professor.university} '
        '${professor.college} ${professor.title}），研究方向：'
        '${professor.researchFields.join('、')}。';
  }

  RecommendationResult? _lastRecommendation(ConversationAggregate aggregate) {
    for (final message in aggregate.messages.reversed) {
      if (message.relatedRecommendations.isNotEmpty) {
        return RecommendationResult(
          sessionId: aggregate.session.id,
          queryUnderstanding: const QueryUnderstanding(
            researchInterests: [],
            preferredLocations: [],
            preferredUniversities: [],
            uncertainties: [],
          ),
          recommendations: message.relatedRecommendations,
          followUpQuestions: const [],
        );
      }
    }
    return null;
  }

  Future<bool> _needsRecommendation(
    ConversationAggregate aggregate,
    String text,
  ) async {
    if (aggregate.session.kind == ConversationSessionKind.general &&
        aggregate.messages.every((message) => message.role == ChatRole.user)) {
      return true;
    }
    return classifier.needRecommendations(
      text,
      lastResult: _lastRecommendation(aggregate),
    );
  }

  Future<List<String>> _quickActions(
    String followUp,
    RecommendationResult? lastResult,
  ) async {
    try {
      final result = await quickActions.fetch(
        followUp: followUp,
        lastResult: lastResult,
      );
      return result is Success<List<String>> ? result.data : const [];
    } catch (_) {
      return const [];
    }
  }

  String _openingLine(RecommendationResult result) {
    final count = result.recommendations.length;
    if (count == 0) return '暂未找到完全符合条件的导师，可以尝试放宽限制。';
    return '为你挑了 $count 位合适的导师，可左右滑动查看：';
  }

  Future<void> _ready() async => initialize?.call();
}
