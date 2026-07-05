import '../../core/ids/uuid_v7.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_aggregate.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/conversation_turn.dart';
import 'conversation_store.dart';

class MemoryConversationStore implements ConversationStore {
  MemoryConversationStore({UuidV7? ids}) : ids = ids ?? UuidV7();

  @override
  final UuidV7 ids;

  final Map<String, ConversationSession> _sessions = {};
  final Map<String, ConversationTurn> _turns = {};
  final Map<String, AssistantAttempt> _attempts = {};
  final Map<String, ChatMessage> _messages = {};
  final Map<String, _StoredMessage> _messageIndex = {};
  final Map<String, List<ConversationCheckpoint>> _checkpoints = {};
  final Map<String, _ForkSourceSnapshot> _forkSources = {};

  @override
  Future<ConversationSession> createSession({
    String? professorId,
    String ownerId = conversationLocalOwnerId,
    String? preferredId,
    String? title,
    bool legacyContextIncomplete = false,
  }) async {
    final now = DateTime.now();
    final id = preferredId ?? ids.generate();
    final existing = _sessions[id];
    if (existing != null && !existing.isDeleted) return existing;
    final session = ConversationSession(
      id: id,
      kind: professorId == null
          ? ConversationSessionKind.general
          : ConversationSessionKind.professor,
      rootSessionId: id,
      professorId: professorId,
      ownerId: ownerId,
      revision: 0,
      title: title,
      createdAt: now,
      updatedAt: now,
      legacyContextIncomplete: legacyContextIncomplete,
    );
    _sessions[id] = session;
    return session;
  }

  @override
  Future<ConversationSession?> getSession(String rawId) async {
    final session = _sessions[rawId];
    if (session == null || session.isDeleted) return null;
    return session;
  }

  @override
  Future<ConversationAggregate?> loadAggregate(
    String rawId, {
    bool includeInherited = false,
  }) async {
    final session = await getSession(rawId);
    if (session == null) return null;

    final turns = <ConversationTurn>[];
    final messages = <ChatMessage>[];
    if (includeInherited && session.kind == ConversationSessionKind.fork) {
      final snapshot = _forkSources[session.id];
      if (snapshot != null) {
        turns.addAll(snapshot.turns);
        messages.addAll(snapshot.messages);
      } else {
        final sourceTurn = _turns[session.sourceTurnId];
        if (sourceTurn != null) {
          final inheritedTurns = _turnsForSession(session.sourceSessionId!)
              .where((turn) => turn.ordinal <= sourceTurn.ordinal)
              .toList(growable: false);
          turns.addAll(inheritedTurns);
          messages.addAll(_visibleMessagesForTurns(inheritedTurns));
        }
      }
    }

    final ownTurns = _turnsForSession(session.id);
    turns.addAll(ownTurns);
    messages.addAll(_visibleMessagesForTurns(ownTurns));

    return ConversationAggregate(
      session: session,
      turns: List.unmodifiable(turns),
      messages: List.unmodifiable(messages),
    );
  }

  @override
  Future<ConversationSession> forkAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
    String ownerId = conversationLocalOwnerId,
  }) async {
    final source = await getSession(sourceSessionId);
    if (source == null || source.isDeleted) {
      throw StateError('source session not found');
    }
    final turn = _turns[sourceTurnId];
    if (turn == null ||
        turn.sessionId != source.id ||
        turn.status != ConversationTurnStatus.completed) {
      throw StateError('source turn is not completed');
    }
    final activeAttemptId = turn.activeAttemptId;
    final sourceMessages = _visibleMessagesForTurns([turn]);
    final containsProfessor = sourceMessages
        .expand((message) => message.relatedRecommendations)
        .any((recommendation) => recommendation.professorId == professorId);
    if (!containsProfessor) {
      throw StateError('professor is not present in source turn');
    }
    final existing = _sessions.values.where((session) {
      final snapshot = _forkSources[session.id];
      return !session.isDeleted &&
          session.sourceSessionId == sourceSessionId &&
          session.sourceTurnId == sourceTurnId &&
          session.professorId == professorId &&
          snapshot?.sourceAttemptId == activeAttemptId;
    }).firstOrNull;
    if (existing != null) return existing;

    final inheritedTurns = _turnsForSession(source.id)
        .where((candidate) => candidate.ordinal <= turn.ordinal)
        .toList(growable: false);
    final inheritedMessages = _visibleMessagesForTurns(inheritedTurns);
    final now = DateTime.now();
    final fork = ConversationSession(
      id: ids.generate(),
      kind: ConversationSessionKind.fork,
      rootSessionId: source.rootSessionId,
      sourceSessionId: source.id,
      sourceTurnId: sourceTurnId,
      professorId: professorId,
      ownerId: ownerId,
      revision: 0,
      createdAt: now,
      updatedAt: now,
    );
    _sessions[fork.id] = fork;
    _forkSources[fork.id] = _ForkSourceSnapshot(
      sourceAttemptId: activeAttemptId,
      turns: List.unmodifiable(inheritedTurns),
      messages: List.unmodifiable(inheritedMessages),
    );
    return fork;
  }

  @override
  Future<({ConversationTurn turn, AssistantAttempt attempt})> beginTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) async {
    final session = await getSession(sessionId);
    if (session == null) throw StateError('session not found');
    if (session.revision != expectedRevision) {
      throw StateError('revision conflict');
    }
    final active = _turnsForSession(session.id).where((turn) {
      return const {
        ConversationTurnStatus.queued,
        ConversationTurnStatus.classifying,
        ConversationTurnStatus.connecting,
        ConversationTurnStatus.streaming,
        ConversationTurnStatus.recommending,
      }.contains(turn.status);
    }).firstOrNull;
    if (active != null) {
      throw StateError('session already has an active turn');
    }

    final now = DateTime.now();
    final turnId = ids.generate();
    final messageId = ids.generate();
    final attemptId = ids.generate();
    final userMessage = ChatMessage(
      id: messageId,
      role: ChatRole.user,
      content: text,
      createdAt: now,
      relatedRecommendations: const [],
      status: ChatMessageStatus.done,
    );
    final turn = ConversationTurn(
      id: turnId,
      sessionId: session.id,
      ordinal: _turnsForSession(session.id).length,
      status: ConversationTurnStatus.queued,
      userMessage: userMessage,
      activeAttemptId: attemptId,
      createdAt: now,
      updatedAt: now,
    );
    final attempt = AssistantAttempt(
      id: attemptId,
      turnId: turnId,
      requestId: requestId ?? ids.generate(),
      status: AssistantAttemptStatus.connecting,
      createdAt: now,
      updatedAt: now,
    );
    _turns[turnId] = turn;
    _attempts[attemptId] = attempt;
    _insertMessage(sessionId: session.id, turnId: turnId, message: userMessage);
    if (session.title == null || session.title!.trim().isEmpty) {
      _sessions[session.id] = _copySession(
        session,
        title: text.length > 60 ? '${text.substring(0, 60)}...' : text,
        updatedAt: now,
      );
    }
    return (turn: turn, attempt: attempt);
  }

  @override
  Future<void> setTurnPhase(
    String turnId,
    ConversationTurnStatus status, {
    ConversationRoute? route,
  }) async {
    final turn = _turns[turnId];
    if (turn == null) return;
    _turns[turnId] = _copyTurn(
      turn,
      status: status,
      route: route ?? turn.route,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<AssistantAttempt> beginRegeneration({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) async {
    final session = await getSession(sessionId);
    if (session == null || session.revision != expectedRevision) {
      throw StateError('revision conflict');
    }
    final turn = _turns[turnId];
    if (turn == null || turn.sessionId != session.id) {
      throw StateError('turn cannot be regenerated');
    }
    if (!const {
      ConversationTurnStatus.completed,
      ConversationTurnStatus.failed,
      ConversationTurnStatus.interrupted,
    }.contains(turn.status)) {
      throw StateError('turn cannot be regenerated');
    }
    final now = DateTime.now();
    final attempt = AssistantAttempt(
      id: ids.generate(),
      turnId: turnId,
      requestId: requestId ?? ids.generate(),
      status: AssistantAttemptStatus.connecting,
      createdAt: now,
      updatedAt: now,
    );
    _attempts[attempt.id] = attempt;
    _turns[turnId] = _copyTurn(
      turn,
      status: ConversationTurnStatus.connecting,
      activeAttemptId: attempt.id,
      updatedAt: now,
    );
    return attempt;
  }

  @override
  Future<void> interruptAttempt(String attemptId, {String partial = ''}) async {
    final attempt = _attempts[attemptId];
    if (attempt == null ||
        !const {
          AssistantAttemptStatus.connecting,
          AssistantAttemptStatus.streaming,
        }.contains(attempt.status)) {
      return;
    }
    final turn = _turns[attempt.turnId];
    if (turn == null) return;
    if (partial.isNotEmpty) {
      final message = ChatMessage(
        id: ids.generate(),
        role: ChatRole.assistant,
        content: partial,
        createdAt: DateTime.now(),
        relatedRecommendations: const [],
        status: ChatMessageStatus.interrupted,
      );
      _insertMessage(
        sessionId: turn.sessionId,
        turnId: turn.id,
        attemptId: attempt.id,
        message: message,
      );
      _attempts[attempt.id] = _copyAttempt(attempt, assistantMessage: message);
    }
    await failAttempt(
      turnId: attempt.turnId,
      attemptId: attempt.id,
      interrupted: true,
    );
  }

  @override
  Future<ChatMessage> completeAttempt({
    required String sessionId,
    required String turnId,
    required String attemptId,
    required ChatMessage message,
  }) async {
    final stored = message.copyWith(
      id: message.id.isEmpty ? ids.generate() : message.id,
      status: ChatMessageStatus.done,
    );
    _insertMessage(
      sessionId: sessionId,
      turnId: turnId,
      attemptId: attemptId,
      message: stored,
    );
    final now = DateTime.now();
    final attempt = _attempts[attemptId];
    if (attempt != null) {
      _attempts[attemptId] = _copyAttempt(
        attempt,
        status: AssistantAttemptStatus.completed,
        assistantMessage: stored,
        updatedAt: now,
      );
    }
    await setTurnPhase(turnId, ConversationTurnStatus.completed);
    _bumpSession(sessionId, now);
    return stored;
  }

  @override
  Future<void> failAttempt({
    required String turnId,
    required String attemptId,
    String? errorCode,
    bool interrupted = false,
  }) async {
    final now = DateTime.now();
    final attempt = _attempts[attemptId];
    if (attempt != null) {
      _attempts[attemptId] = _copyAttempt(
        attempt,
        status: interrupted
            ? AssistantAttemptStatus.interrupted
            : AssistantAttemptStatus.failed,
        errorCode: errorCode,
        updatedAt: now,
      );
    }
    final turn = _turns[turnId];
    if (turn == null) return;
    await setTurnPhase(
      turnId,
      interrupted
          ? ConversationTurnStatus.interrupted
          : ConversationTurnStatus.failed,
    );
    _bumpSession(turn.sessionId, now);
  }

  @override
  Future<void> setFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async {
    final message = _messages[messageId];
    if (message == null) throw StateError('message not found');
    _messages[messageId] = message.copyWith(feedback: feedback);
  }

  @override
  Future<List<ConversationSession>> listSessions({
    bool rootsOnly = true,
  }) async {
    final result = _sessions.values
        .where((session) {
          return !session.isDeleted &&
              (!rootsOnly || session.kind != ConversationSessionKind.fork);
        })
        .toList(growable: false);
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<List<ConversationSession>> listForks(String rootSessionId) async {
    final result = _sessions.values
        .where((session) {
          return !session.isDeleted &&
              session.rootSessionId == rootSessionId &&
              session.kind == ConversationSessionKind.fork;
        })
        .toList(growable: false);
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> deleteSession(String rawId) async {
    final session = await getSession(rawId);
    if (session == null) return;
    final sessionIds = session.kind == ConversationSessionKind.fork
        ? {session.id}
        : _sessions.values
              .where((s) => s.rootSessionId == session.rootSessionId)
              .map((s) => s.id)
              .toSet();
    for (final id in sessionIds) {
      _sessions.remove(id);
      _checkpoints.remove(id);
      _forkSources.remove(id);
    }
    final turnIds = _turns.values
        .where((turn) => sessionIds.contains(turn.sessionId))
        .map((turn) => turn.id)
        .toSet();
    for (final id in turnIds) {
      _turns.remove(id);
    }
    _attempts.removeWhere((_, attempt) => turnIds.contains(attempt.turnId));
    final messageIds = _messageIndex.entries
        .where((entry) => sessionIds.contains(entry.value.sessionId))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in messageIds) {
      _messages.remove(id);
      _messageIndex.remove(id);
    }
  }

  @override
  Future<void> clearSessions() async {
    _sessions.clear();
    _turns.clear();
    _attempts.clear();
    _messages.clear();
    _messageIndex.clear();
    _checkpoints.clear();
    _forkSources.clear();
  }

  @override
  Future<ConversationCheckpoint?> latestCheckpoint(String sessionId) async {
    final checkpoints = List<ConversationCheckpoint>.of(
      _checkpoints[sessionId] ?? const [],
    );
    checkpoints.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return checkpoints.firstOrNull;
  }

  @override
  Future<void> saveCheckpoint({
    required String sessionId,
    required String throughTurnId,
    required String summary,
    required String modelVersion,
    String factsJson = '{}',
  }) async {
    final checkpoint = ConversationCheckpoint(
      id: ids.generate(),
      sessionId: sessionId,
      throughTurnId: throughTurnId,
      summary: summary,
      factsJson: factsJson,
      modelVersion: modelVersion,
      createdAt: DateTime.now(),
    );
    (_checkpoints[sessionId] ??= []).add(checkpoint);
  }

  Future<void> importLegacyMessages(
    String sessionId,
    List<ChatMessage> legacyMessages,
  ) async {
    var ordinal = 0;
    String? turnId;
    for (final legacy in legacyMessages) {
      if (legacy.role == ChatRole.user) {
        turnId = ids.generate();
        final message = legacy.copyWith(id: ids.generate());
        _turns[turnId] = ConversationTurn(
          id: turnId,
          sessionId: sessionId,
          ordinal: ordinal++,
          status: ConversationTurnStatus.interrupted,
          userMessage: message,
          createdAt: legacy.createdAt,
          updatedAt: legacy.createdAt,
        );
        _insertMessage(sessionId: sessionId, turnId: turnId, message: message);
        continue;
      }
      if (turnId == null) continue;
      final attemptId = ids.generate();
      final status = legacy.status == ChatMessageStatus.error
          ? AssistantAttemptStatus.failed
          : AssistantAttemptStatus.completed;
      final message = legacy.copyWith(
        id: ids.generate(),
        status: legacy.status == ChatMessageStatus.error
            ? ChatMessageStatus.error
            : ChatMessageStatus.done,
      );
      _attempts[attemptId] = AssistantAttempt(
        id: attemptId,
        turnId: turnId,
        requestId: ids.generate(),
        status: status,
        assistantMessage: message,
        createdAt: legacy.createdAt,
        updatedAt: legacy.createdAt,
      );
      _insertMessage(
        sessionId: sessionId,
        turnId: turnId,
        attemptId: attemptId,
        message: message,
      );
      final route = switch (legacy.kind) {
        ChatMessageKind.recommendation => ConversationRoute.recommendation,
        ChatMessageKind.forkReroute => ConversationRoute.forkReroute,
        ChatMessageKind.conversation => ConversationRoute.conversation,
      };
      final turn = _turns[turnId]!;
      _turns[turnId] = _copyTurn(
        turn,
        status: legacy.status == ChatMessageStatus.error
            ? ConversationTurnStatus.failed
            : ConversationTurnStatus.completed,
        route: route,
        activeAttemptId: attemptId,
        updatedAt: legacy.createdAt,
      );
    }
    final session = _sessions[sessionId];
    if (session != null) {
      _sessions[sessionId] = _copySession(
        session,
        revision: ordinal,
        updatedAt: legacyMessages.isEmpty
            ? DateTime.now()
            : legacyMessages.last.createdAt,
      );
    }
  }

  List<ConversationTurn> _turnsForSession(String sessionId) {
    final result = _turns.values
        .where((turn) => turn.sessionId == sessionId)
        .toList(growable: false);
    result.sort((a, b) => a.ordinal.compareTo(b.ordinal));
    return result;
  }

  List<ChatMessage> _visibleMessagesForTurns(List<ConversationTurn> turns) {
    final turnIds = turns.map((turn) => turn.id).toSet();
    final activeAttempts = {
      for (final turn in turns) turn.id: turn.activeAttemptId,
    };
    final entries = _messageIndex.entries
        .where((entry) {
          final index = entry.value;
          if (!turnIds.contains(index.turnId)) return false;
          final message = _messages[entry.key];
          if (message == null) return false;
          return message.role == ChatRole.user ||
              index.attemptId == activeAttempts[index.turnId];
        })
        .toList(growable: false);
    entries.sort((a, b) => a.value.position.compareTo(b.value.position));
    return entries
        .map((entry) => _messages[entry.key])
        .whereType<ChatMessage>()
        .toList();
  }

  void _insertMessage({
    required String sessionId,
    required String turnId,
    required ChatMessage message,
    String? attemptId,
  }) {
    final position =
        _messageIndex.values
            .where((index) => index.sessionId == sessionId)
            .fold<int>(
              -1,
              (max, index) => index.position > max ? index.position : max,
            ) +
        1;
    _messages[message.id] = message;
    _messageIndex[message.id] = _StoredMessage(
      sessionId: sessionId,
      turnId: turnId,
      attemptId: attemptId,
      position: position,
    );
  }

  void _bumpSession(String sessionId, DateTime updatedAt) {
    final session = _sessions[sessionId];
    if (session == null) return;
    _sessions[sessionId] = _copySession(
      session,
      revision: session.revision + 1,
      updatedAt: updatedAt,
    );
  }

  ConversationSession _copySession(
    ConversationSession session, {
    int? revision,
    String? title,
    DateTime? updatedAt,
  }) {
    return ConversationSession(
      id: session.id,
      kind: session.kind,
      rootSessionId: session.rootSessionId,
      ownerId: session.ownerId,
      revision: revision ?? session.revision,
      createdAt: session.createdAt,
      updatedAt: updatedAt ?? session.updatedAt,
      sourceSessionId: session.sourceSessionId,
      sourceTurnId: session.sourceTurnId,
      professorId: session.professorId,
      title: title ?? session.title,
      deletedAt: session.deletedAt,
      legacyContextIncomplete: session.legacyContextIncomplete,
    );
  }

  ConversationTurn _copyTurn(
    ConversationTurn turn, {
    ConversationTurnStatus? status,
    ConversationRoute? route,
    String? activeAttemptId,
    DateTime? updatedAt,
  }) {
    return ConversationTurn(
      id: turn.id,
      sessionId: turn.sessionId,
      ordinal: turn.ordinal,
      status: status ?? turn.status,
      route: route ?? turn.route,
      userMessage: turn.userMessage,
      activeAttemptId: activeAttemptId ?? turn.activeAttemptId,
      createdAt: turn.createdAt,
      updatedAt: updatedAt ?? turn.updatedAt,
    );
  }

  AssistantAttempt _copyAttempt(
    AssistantAttempt attempt, {
    AssistantAttemptStatus? status,
    ChatMessage? assistantMessage,
    String? errorCode,
    DateTime? updatedAt,
  }) {
    return AssistantAttempt(
      id: attempt.id,
      turnId: attempt.turnId,
      requestId: attempt.requestId,
      status: status ?? attempt.status,
      assistantMessage: assistantMessage ?? attempt.assistantMessage,
      errorCode: errorCode ?? attempt.errorCode,
      createdAt: attempt.createdAt,
      updatedAt: updatedAt ?? attempt.updatedAt,
    );
  }
}

class _ForkSourceSnapshot {
  const _ForkSourceSnapshot({
    required this.sourceAttemptId,
    required this.turns,
    required this.messages,
  });

  final String? sourceAttemptId;
  final List<ConversationTurn> turns;
  final List<ChatMessage> messages;
}

class _StoredMessage {
  const _StoredMessage({
    required this.sessionId,
    required this.turnId,
    required this.position,
    this.attemptId,
  });

  final String sessionId;
  final String turnId;
  final String? attemptId;
  final int position;
}
