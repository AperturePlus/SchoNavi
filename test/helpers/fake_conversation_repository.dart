import 'dart:async';

import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/conversation_turn.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';

final fakeNow = DateTime.utc(2026, 6, 27, 12);

ConversationSession fakeSession({
  String id = 'session-1',
  ConversationSessionKind kind = ConversationSessionKind.general,
  String? rootSessionId,
  String? sourceSessionId,
  String? sourceTurnId,
  String? professorId,
  int revision = 0,
  String? title,
  DateTime? createdAt,
  DateTime? updatedAt,
  bool legacyContextIncomplete = false,
}) {
  return ConversationSession(
    id: id,
    kind: kind,
    rootSessionId: rootSessionId ?? id,
    sourceSessionId: sourceSessionId,
    sourceTurnId: sourceTurnId,
    professorId: professorId,
    ownerId: 'test-user',
    revision: revision,
    title: title,
    createdAt: createdAt ?? fakeNow,
    updatedAt: updatedAt ?? fakeNow,
    legacyContextIncomplete: legacyContextIncomplete,
  );
}

ChatMessage fakeUserMessage({
  String id = 'user-1',
  String content = '问题',
  DateTime? createdAt,
}) {
  return ChatMessage(
    id: id,
    role: ChatRole.user,
    content: content,
    createdAt: createdAt ?? fakeNow,
    relatedRecommendations: const [],
    status: ChatMessageStatus.done,
  );
}

ChatMessage fakeAssistantMessage({
  String id = 'assistant-1',
  String content = '回答',
  ChatMessageStatus status = ChatMessageStatus.done,
  ChatMessageKind kind = ChatMessageKind.conversation,
  List<Recommendation> relatedRecommendations = const [],
  DateTime? createdAt,
}) {
  return ChatMessage(
    id: id,
    role: ChatRole.assistant,
    content: content,
    createdAt: createdAt ?? fakeNow,
    relatedRecommendations: relatedRecommendations,
    status: status,
    kind: kind,
  );
}

ConversationTurn fakeTurn({
  String id = 'turn-1',
  String sessionId = 'session-1',
  int ordinal = 0,
  ConversationTurnStatus status = ConversationTurnStatus.completed,
  ConversationRoute route = ConversationRoute.conversation,
  ChatMessage? userMessage,
  String? activeAttemptId = 'attempt-1',
}) {
  return ConversationTurn(
    id: id,
    sessionId: sessionId,
    ordinal: ordinal,
    status: status,
    route: route,
    userMessage: userMessage ?? fakeUserMessage(),
    activeAttemptId: activeAttemptId,
    createdAt: fakeNow,
    updatedAt: fakeNow,
  );
}

ConversationAggregate fakeAggregate({
  ConversationSession? session,
  List<ConversationTurn> turns = const [],
  List<ChatMessage> messages = const [],
}) {
  return ConversationAggregate(
    session: session ?? fakeSession(),
    turns: turns,
    messages: messages,
  );
}

class SubmitTurnCall {
  const SubmitTurnCall({
    required this.sessionId,
    required this.text,
    required this.expectedRevision,
    this.requestId,
  });

  final String sessionId;
  final String text;
  final int expectedRevision;
  final String? requestId;
}

class RegenerateTurnCall {
  const RegenerateTurnCall({
    required this.sessionId,
    required this.turnId,
    required this.expectedRevision,
    this.requestId,
  });

  final String sessionId;
  final String turnId;
  final int expectedRevision;
  final String? requestId;
}

class ControllableConversationRepository implements ConversationRepository {
  ControllableConversationRepository({
    ConversationAggregate? initialAggregate,
  }) {
    final aggregate = initialAggregate ?? fakeAggregate();
    aggregates[aggregate.session.id] = aggregate;
  }

  final Map<String, ConversationAggregate> aggregates = {};
  final List<SubmitTurnCall> submitCalls = [];
  final List<RegenerateTurnCall> regenerateCalls = [];
  final List<String> cancelCalls = [];
  final List<String> deletedSessions = [];
  int clearSessionsCalls = 0;
  int listSessionsCalls = 0;
  final List<ChatMessageFeedback> feedbackCalls = [];

  Result<ConversationAggregate>? loadResult;
  Result<ConversationSession>? createResult;
  Result<void> cancelResult = const Success(null);
  Result<void> deleteResult = const Success(null);
  Result<void> feedbackResult = const Success(null);

  int createCalls = 0;
  int loadCalls = 0;
  int forkCalls = 0;

  final List<Completer<Result<ConversationAggregate>>> _parkedLoads = [];
  final List<Completer<Result<ConversationSession>>> _parkedForks = [];
  final List<StreamController<ConversationEvent>> eventControllers = [];

  StreamController<ConversationEvent>? get activeEvents =>
      eventControllers.isEmpty ? null : eventControllers.last;

  Completer<Result<ConversationAggregate>> parkNextLoad() {
    final completer = Completer<Result<ConversationAggregate>>();
    _parkedLoads.add(completer);
    return completer;
  }

  Completer<Result<ConversationSession>> parkNextFork() {
    final completer = Completer<Result<ConversationSession>>();
    _parkedForks.add(completer);
    return completer;
  }

  void setAggregate(ConversationAggregate aggregate) {
    aggregates[aggregate.session.id] = aggregate;
  }

  void emit(ConversationEvent event) {
    activeEvents?.add(event);
  }

  Future<void> closeActiveEvents() async {
    closeActiveEventsSync();
    await Future<void>.delayed(Duration.zero);
  }

  void closeActiveEventsSync() {
    final controller = activeEvents;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  @override
  Future<Result<ConversationSession>> createSession({String? professorId}) async {
    createCalls++;
    if (createResult != null) return createResult!;
    final id = professorId == null ? 'session-1' : 'session-$professorId';
    final session = fakeSession(
      id: id,
      kind: professorId == null
          ? ConversationSessionKind.general
          : ConversationSessionKind.professor,
      professorId: professorId,
    );
    aggregates.putIfAbsent(id, () => fakeAggregate(session: session));
    return Success(session);
  }

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async {
    loadCalls++;
    if (_parkedLoads.isNotEmpty) return _parkedLoads.removeAt(0).future;
    if (loadResult != null) return loadResult!;
    final aggregate = aggregates[sessionId];
    if (aggregate == null) {
      return const Failure(NotFoundException());
    }
    return Success(aggregate);
  }

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async {
    forkCalls++;
    if (_parkedForks.isNotEmpty) return _parkedForks.removeAt(0).future;
    final id = 'fork-$sourceSessionId-$professorId';
    final session = fakeSession(
      id: id,
      kind: ConversationSessionKind.fork,
      rootSessionId: sourceSessionId,
      sourceSessionId: sourceSessionId,
      sourceTurnId: sourceTurnId,
      professorId: professorId,
    );
    final source = aggregates[sourceSessionId];
    aggregates[id] = fakeAggregate(
      session: session,
      turns: source?.turns ?? const [],
      messages: source?.messages ?? const [],
    );
    return Success(session);
  }

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) {
    submitCalls.add(
      SubmitTurnCall(
        sessionId: sessionId,
        text: text,
        expectedRevision: expectedRevision,
        requestId: requestId,
      ),
    );
    final controller = StreamController<ConversationEvent>.broadcast();
    eventControllers.add(controller);
    return controller.stream;
  }

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) {
    regenerateCalls.add(
      RegenerateTurnCall(
        sessionId: sessionId,
        turnId: turnId,
        expectedRevision: expectedRevision,
        requestId: requestId,
      ),
    );
    final controller = StreamController<ConversationEvent>.broadcast();
    eventControllers.add(controller);
    return controller.stream;
  }

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async {
    cancelCalls.add(attemptId);
    closeActiveEventsSync();
    return cancelResult;
  }

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async {
    feedbackCalls.add(feedback);
    return feedbackResult;
  }

  @override
  Future<Result<List<ConversationSession>>> listSessions() async {
    listSessionsCalls++;
    return Success(aggregates.values.map((a) => a.session).toList());
  }

  @override
  Future<Result<List<ConversationSession>>> listForks(String rootSessionId) async {
    return Success(
      aggregates.values
          .map((a) => a.session)
          .where((s) => s.kind == ConversationSessionKind.fork)
          .where((s) => s.rootSessionId == rootSessionId)
          .toList(),
    );
  }

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    deletedSessions.add(sessionId);
    return deleteResult;
  }

  @override
  Future<Result<void>> clearSessions() async {
    clearSessionsCalls++;
    if (deleteResult is Success<void>) {
      aggregates.clear();
    }
    return deleteResult;
  }

  Future<void> dispose() async {
    for (final controller in eventControllers) {
      if (!controller.isClosed) unawaited(controller.close());
    }
  }
}

ConversationAcknowledged acknowledged({
  String sessionId = 'session-1',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 0,
}) {
  return ConversationAcknowledged(
    sessionId: sessionId,
    turnId: turnId,
    attemptId: attemptId,
    revision: revision,
  );
}

ConversationRouted routed({
  String sessionId = 'session-1',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 0,
  ConversationRoute route = ConversationRoute.conversation,
}) {
  return ConversationRouted(
    sessionId: sessionId,
    turnId: turnId,
    attemptId: attemptId,
    revision: revision,
    route: route,
  );
}

ConversationDelta delta({
  String sessionId = 'session-1',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 0,
  String text = '回答',
}) {
  return ConversationDelta(
    sessionId: sessionId,
    turnId: turnId,
    attemptId: attemptId,
    revision: revision,
    text: text,
  );
}

ConversationCompleted completed({
  String sessionId = 'session-1',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 1,
  ChatMessage? message,
  ConversationSession? session,
  List<String> quickActions = const [],
}) {
  return ConversationCompleted(
    sessionId: sessionId,
    turnId: turnId,
    attemptId: attemptId,
    revision: revision,
    message: message ?? fakeAssistantMessage(),
    session: session ?? fakeSession(id: sessionId, revision: revision),
    quickActions: quickActions,
  );
}

ConversationFailed failed({
  String sessionId = 'session-1',
  String turnId = 'turn-1',
  String attemptId = 'attempt-1',
  int revision = 0,
  String message = '服务异常，请稍后重试',
  String? code,
  String? requestId,
  String? path,
}) {
  return ConversationFailed(
    sessionId: sessionId,
    turnId: turnId,
    attemptId: attemptId,
    revision: revision,
    message: message,
    code: code,
    requestId: requestId,
    path: path,
  );
}
