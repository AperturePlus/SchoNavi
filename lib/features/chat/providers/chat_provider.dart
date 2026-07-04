import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/error_diagnostics.dart';
import '../../../core/ids/uuid_v7.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/conversation_aggregate.dart';
import '../../../domain/entities/conversation_event.dart';
import '../../../domain/entities/conversation_session.dart';
import '../../../domain/entities/conversation_turn.dart';
import '../../../domain/entities/fork_ref.dart';

enum ChatActivity {
  unloaded,
  creating,
  hydrating,
  idle,
  classifying,
  connecting,
  streaming,
  recommending,
  committing,
  cancelling,
  loadFailed,
  turnFailed,
  interrupted,
  deleting,
  deleted,
}

class _Sentinel {
  const _Sentinel();
}

const _sentinel = _Sentinel();

class ChatState {
  const ChatState({
    required this.sessionId,
    required this.professorId,
    required this.messages,
    required this.activity,
    required this.followUpQuestions,
    this.forkAnchor,
    this.kind = ConversationSessionKind.general,
    this.rootSessionId,
    this.sourceSessionId,
    this.sourceTurnId,
    this.revision = 0,
    this.turns = const [],
    this.activeTurnId,
    this.activeAttemptId,
    this.error,
    this.legacyContextIncomplete = false,
  });

  const ChatState.initial()
    : sessionId = null,
      professorId = null,
      messages = const [],
      activity = ChatActivity.unloaded,
      followUpQuestions = const [],
      forkAnchor = null,
      kind = ConversationSessionKind.general,
      rootSessionId = null,
      sourceSessionId = null,
      sourceTurnId = null,
      revision = 0,
      turns = const [],
      activeTurnId = null,
      activeAttemptId = null,
      error = null,
      legacyContextIncomplete = false;

  final String? sessionId;
  final String? professorId;
  final List<ChatMessage> messages;
  final ChatActivity activity;
  final List<String> followUpQuestions;
  final ForkRef? forkAnchor;
  final ConversationSessionKind kind;
  final String? rootSessionId;
  final String? sourceSessionId;
  final String? sourceTurnId;
  final int revision;
  final List<ConversationTurn> turns;
  final String? activeTurnId;
  final String? activeAttemptId;
  final AppException? error;
  String? get errorMessage => error?.message;
  final bool legacyContextIncomplete;

  bool get isBusy => switch (activity) {
    ChatActivity.creating ||
    ChatActivity.hydrating ||
    ChatActivity.classifying ||
    ChatActivity.connecting ||
    ChatActivity.streaming ||
    ChatActivity.recommending ||
    ChatActivity.committing ||
    ChatActivity.cancelling ||
    ChatActivity.deleting => true,
    _ => false,
  };

  bool get isResponding => isBusy;
  bool get canSend =>
      activity == ChatActivity.idle &&
      sessionId != null &&
      !legacyContextIncomplete;

  bool get canRegenerate {
    if (isBusy || turns.isEmpty) return false;
    final turn = turns.last;
    if (turn.sessionId != sessionId) return false;
    if (turn.status == ConversationTurnStatus.failed ||
        turn.status == ConversationTurnStatus.interrupted) {
      return turn.route != ConversationRoute.forkReroute;
    }
    if (messages.length < 2) return false;
    final assistant = messages.last;
    return assistant.role == ChatRole.assistant &&
        assistant.kind == ChatMessageKind.conversation &&
        turn.route == ConversationRoute.conversation &&
        turn.status == ConversationTurnStatus.completed;
  }

  ChatState copyWith({
    Object? sessionId = _sentinel,
    Object? professorId = _sentinel,
    List<ChatMessage>? messages,
    ChatActivity? activity,
    List<String>? followUpQuestions,
    Object? forkAnchor = _sentinel,
    ConversationSessionKind? kind,
    Object? rootSessionId = _sentinel,
    Object? sourceSessionId = _sentinel,
    Object? sourceTurnId = _sentinel,
    int? revision,
    List<ConversationTurn>? turns,
    Object? activeTurnId = _sentinel,
    Object? activeAttemptId = _sentinel,
    Object? error = _sentinel,
    bool? legacyContextIncomplete,
  }) => ChatState(
    sessionId: identical(sessionId, _sentinel)
        ? this.sessionId
        : sessionId as String?,
    professorId: identical(professorId, _sentinel)
        ? this.professorId
        : professorId as String?,
    messages: messages ?? this.messages,
    activity: activity ?? this.activity,
    followUpQuestions: followUpQuestions ?? this.followUpQuestions,
    forkAnchor: identical(forkAnchor, _sentinel)
        ? this.forkAnchor
        : forkAnchor as ForkRef?,
    kind: kind ?? this.kind,
    rootSessionId: identical(rootSessionId, _sentinel)
        ? this.rootSessionId
        : rootSessionId as String?,
    sourceSessionId: identical(sourceSessionId, _sentinel)
        ? this.sourceSessionId
        : sourceSessionId as String?,
    sourceTurnId: identical(sourceTurnId, _sentinel)
        ? this.sourceTurnId
        : sourceTurnId as String?,
    revision: revision ?? this.revision,
    turns: turns ?? this.turns,
    activeTurnId: identical(activeTurnId, _sentinel)
        ? this.activeTurnId
        : activeTurnId as String?,
    activeAttemptId: identical(activeAttemptId, _sentinel)
        ? this.activeAttemptId
        : activeAttemptId as String?,
    error: identical(error, _sentinel) ? this.error : error as AppException?,
    legacyContextIncomplete:
        legacyContextIncomplete ?? this.legacyContextIncomplete,
  );
}

class ChatNotifier extends Notifier<ChatState> {
  final UuidV7 _ids = UuidV7();
  int _operation = 0;
  int? _activeEventRevision;
  StreamIterator<ConversationEvent>? _iterator;

  @override
  ChatState build() {
    ref.onDispose(() {
      _operation++;
      _activeEventRevision = null;
      final iterator = _iterator;
      _iterator = null;
      if (iterator != null) unawaited(iterator.cancel());
    });
    return const ChatState.initial();
  }

  Future<void> create({String? professorId}) async {
    final token = _beginOperation();
    await _cancelIterator();
    state = const ChatState.initial().copyWith(
      activity: ChatActivity.creating,
      professorId: professorId,
    );
    final result = await ref
        .read(conversationRepositoryProvider)
        .createSession(professorId: professorId);
    if (!_isCurrent(token)) return;
    switch (result) {
      case Success<ConversationSession>(:final data):
        await _hydrate(data.id, token: token);
      case Failure<ConversationSession>(:final error):
        state = state.copyWith(activity: ChatActivity.loadFailed, error: error);
    }
  }

  /// Compatibility entry point. Existing IDs are hydrated. A missing or
  /// unreadable ID is a load failure and must never become a new empty chat.
  Future<void> start({required String sessionId, String? professorId}) async {
    final token = _beginOperation();
    await _cancelIterator();
    state = const ChatState.initial().copyWith(
      activity: ChatActivity.hydrating,
      professorId: professorId,
    );
    final loaded = await ref
        .read(conversationRepositoryProvider)
        .loadSession(sessionId);
    if (!_isCurrent(token)) return;
    switch (loaded) {
      case Success<ConversationAggregate>(:final data):
        _applyAggregate(data);
      case Failure<ConversationAggregate>(:final error):
        state = state.copyWith(activity: ChatActivity.loadFailed, error: error);
    }
  }

  Future<void> bootstrapRecommendations(String initialPrompt) =>
      send(initialPrompt);

  Future<void> startFork({
    required String sourceSessionId,
    required String professorId,
    String? sourceTurnId,
  }) async {
    if (sourceSessionId.trim().isEmpty) {
      await create(professorId: professorId);
      return;
    }
    final token = _beginOperation();
    await _cancelIterator();
    state = const ChatState.initial().copyWith(
      activity: ChatActivity.hydrating,
      professorId: professorId,
    );
    final sourceResult = await ref
        .read(conversationRepositoryProvider)
        .loadSession(sourceSessionId);
    if (!_isCurrent(token)) return;
    if (sourceResult is! Success<ConversationAggregate>) {
      state = state.copyWith(
        activity: ChatActivity.loadFailed,
        error: sourceResult is Failure<ConversationAggregate>
            ? sourceResult.error
            : const UnknownException(),
      );
      return;
    }
    final source = sourceResult.data;
    final resolvedTurnId =
        sourceTurnId ?? _latestRecommendationTurn(source, professorId);
    if (resolvedTurnId == null) {
      state = state.copyWith(
        activity: ChatActivity.loadFailed,
        error: const ValidationException('所选导师不属于可追问的推荐轮次'),
      );
      return;
    }
    final fork = await ref
        .read(conversationRepositoryProvider)
        .forkSessionAtTurn(
          sourceSessionId: source.session.id,
          sourceTurnId: resolvedTurnId,
          professorId: professorId,
        );
    if (!_isCurrent(token)) return;
    switch (fork) {
      case Success<ConversationSession>(:final data):
        await _hydrate(data.id, token: token);
      case Failure<ConversationSession>(:final error):
        state = state.copyWith(activity: ChatActivity.loadFailed, error: error);
    }
  }

  Future<void> resume({
    required String sessionId,
    bool isFork = false,
    String? mainSessionId,
  }) async {
    final token = _beginOperation();
    await _cancelIterator();
    state = const ChatState.initial().copyWith(
      activity: ChatActivity.hydrating,
    );
    await _hydrate(sessionId, token: token);
  }

  Future<void> send(String text) async {
    final content = text.trim();
    if (content.isEmpty || !state.canSend) return;
    final sessionId = state.sessionId!;
    final requestId = _ids.generate();
    final expectedRevision = state.revision;
    final optimisticUser = ChatMessage(
      id: 'pending-$requestId',
      role: ChatRole.user,
      content: content,
      createdAt: DateTime.now(),
      relatedRecommendations: const [],
      status: ChatMessageStatus.done,
    );
    state = state.copyWith(
      activity: ChatActivity.classifying,
      messages: [...state.messages, optimisticUser],
      error: null,
    );
    await _runEvents(
      ref
          .read(conversationRepositoryProvider)
          .submitTurn(
            sessionId: sessionId,
            text: content,
            expectedRevision: expectedRevision,
            requestId: requestId,
          ),
      sessionId: sessionId,
      operation: 'submitTurn',
      requestId: requestId,
      expectedRevision: expectedRevision,
      submittedText: content,
    );
  }

  Future<void> regenerate() async {
    if (!state.canRegenerate) return;
    await _regenerateLatest();
  }

  Future<void> regenerateMessage(String assistantMessageId) async {
    if (!state.canRegenerate ||
        state.messages.last.id != assistantMessageId ||
        state.sessionId == null) {
      return;
    }
    await _regenerateLatest();
  }

  Future<void> retryRecommendation(String assistantMessageId) async {
    if (state.isBusy ||
        state.sessionId == null ||
        state.turns.isEmpty ||
        state.messages.isEmpty ||
        state.messages.last.id != assistantMessageId ||
        state.turns.last.route != ConversationRoute.recommendation ||
        state.turns.last.sessionId != state.sessionId) {
      return;
    }
    await _regenerateLatest();
  }

  void setFeedback(String messageId, ChatMessageFeedback feedback) {
    final messages = [...state.messages];
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index == -1 ||
        messages[index].role != ChatRole.assistant ||
        messages[index].status != ChatMessageStatus.done) {
      return;
    }
    final previous = messages[index].feedback;
    messages[index] = messages[index].copyWith(feedback: feedback);
    state = state.copyWith(messages: messages);
    unawaited(_persistFeedback(messageId, previous, feedback));
  }

  Future<void> abandonInterruptedTurn() async {
    if (state.activity != ChatActivity.interrupted &&
        state.activity != ChatActivity.turnFailed) {
      return;
    }
    state = state.copyWith(activity: ChatActivity.idle, error: null);
  }

  Future<void> delete() async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.isBusy) return;
    final token = _beginOperation();
    await _cancelIterator();
    state = state.copyWith(activity: ChatActivity.deleting);
    final result = await ref
        .read(conversationRepositoryProvider)
        .deleteSession(sessionId);
    if (!_isCurrent(token)) return;
    switch (result) {
      case Success<void>():
        state = state.copyWith(
          activity: ChatActivity.deleted,
          messages: const [],
          turns: const [],
          activeTurnId: null,
          activeAttemptId: null,
        );
      case Failure<void>(:final error):
        state = state.copyWith(activity: ChatActivity.turnFailed, error: error);
    }
  }

  Future<void> stop() async {
    if (state.activity != ChatActivity.streaming &&
        state.activity != ChatActivity.connecting) {
      return;
    }
    final attemptId = state.activeAttemptId;
    _operation++;
    _activeEventRevision = null;
    state = state.copyWith(activity: ChatActivity.cancelling);
    await _cancelIterator();
    if (attemptId != null) {
      final cancelResult = await ref
          .read(conversationRepositoryProvider)
          .cancelAttempt(attemptId);
      if (cancelResult case Failure<void>(:final error)) {
        ref.read(apiErrorReporterProvider.notifier).report('停止生成失败', error);
      }
    }
    final sessionId = state.sessionId;
    if (sessionId != null) {
      final token = _beginOperation();
      await _hydrate(sessionId, token: token);
    }
  }

  Future<void> _runEvents(
    Stream<ConversationEvent> stream, {
    required String sessionId,
    required String operation,
    required String requestId,
    required int expectedRevision,
    String? submittedText,
    String? targetTurnId,
  }) async {
    final token = _beginOperation();
    await _cancelIterator();
    final iterator = StreamIterator<ConversationEvent>(stream);
    _iterator = iterator;
    try {
      while (await iterator.moveNext()) {
        if (!_isCurrent(token)) return;
        final event = iterator.current;
        if (!_acceptEvent(event, sessionId)) continue;
        await _handleEvent(
          event,
          token: token,
          operation: operation,
          requestId: requestId,
          expectedRevision: expectedRevision,
          submittedText: submittedText,
          targetTurnId: targetTurnId,
        );
      }
      if (_isCurrent(token) && state.isBusy) {
        await _hydrate(sessionId, token: token);
      }
    } catch (error, stackTrace) {
      if (!_isCurrent(token)) return;
      final appError = _withChatContext(
        normalizeAppException(error, stackTrace),
        operation: operation,
        requestId: requestId,
        expectedRevision: expectedRevision,
        submittedText: submittedText,
        targetTurnId: targetTurnId,
      );
      await _hydrate(sessionId, token: token);
      if (!_isCurrent(token) || state.activity == ChatActivity.loadFailed) {
        return;
      }
      state = state.copyWith(
        activity: ChatActivity.turnFailed,
        error: appError,
        messages: [
          ...state.messages,
          ChatMessage(
            id: _ids.generate(),
            role: ChatRole.assistant,
            content: appError.message,
            createdAt: DateTime.now(),
            relatedRecommendations: const [],
            status: ChatMessageStatus.error,
          ),
        ],
      );
    } finally {
      if (_iterator == iterator) _iterator = null;
      await iterator.cancel();
    }
  }

  Future<void> _handleEvent(
    ConversationEvent event, {
    required int token,
    required String operation,
    required String requestId,
    required int expectedRevision,
    String? submittedText,
    String? targetTurnId,
  }) async {
    switch (event) {
      case ConversationAcknowledged():
        _activeEventRevision = event.revision;
        state = state.copyWith(
          activeTurnId: event.turnId,
          activeAttemptId: event.attemptId,
        );
      case ConversationRouted(:final route):
        final kind = switch (route) {
          ConversationRoute.recommendation => ChatMessageKind.recommendation,
          ConversationRoute.forkReroute => ChatMessageKind.forkReroute,
          ConversationRoute.conversation => ChatMessageKind.conversation,
        };
        final activity = switch (route) {
          ConversationRoute.recommendation => ChatActivity.recommending,
          ConversationRoute.forkReroute => ChatActivity.committing,
          ConversationRoute.conversation => ChatActivity.connecting,
        };
        state = state.copyWith(
          activity: activity,
          messages: [
            ...state.messages,
            ChatMessage(
              id: 'pending-${event.attemptId}',
              role: ChatRole.assistant,
              content: '',
              createdAt: DateTime.now(),
              relatedRecommendations: const [],
              status: ChatMessageStatus.sending,
              kind: kind,
            ),
          ],
        );
      case ConversationDelta(:final text):
        final id = 'pending-${event.attemptId}';
        final messages = [...state.messages];
        final index = messages.indexWhere((m) => m.id == id);
        if (index != -1) {
          messages[index] = messages[index].copyWith(
            content: '${messages[index].content}$text',
            status: ChatMessageStatus.streaming,
          );
        }
        state = state.copyWith(
          activity: ChatActivity.streaming,
          messages: messages,
        );
      case ConversationCompleted(:final message, :final quickActions):
        state = state.copyWith(activity: ChatActivity.committing);
        await _hydrate(event.sessionId, token: token);
        if (_isCurrent(token)) {
          state = state.copyWith(
            activity: ChatActivity.idle,
            messages: _mergeCompletedMessage(
              state.messages,
              message,
              attemptId: event.attemptId,
            ),
            followUpQuestions: quickActions,
            activeTurnId: null,
            activeAttemptId: null,
          );
          _activeEventRevision = null;
        }
      case ConversationFailed(:final message):
        final appError = _withChatContext(
          ValidationException(
            message,
            diagnostics: ErrorDiagnostics(
              requestId: event.requestId ?? requestId,
              method: 'POST',
              path: event.path,
              backendCode: event.code,
              backendMessage: message,
              exceptionType: 'ConversationStreamException',
              occurredAt: DateTime.now(),
              context: {
                '事件会话 ID': event.sessionId,
                '事件轮次 ID': event.turnId,
                '事件尝试 ID': event.attemptId,
                '事件 revision': event.revision.toString(),
              },
            ),
          ),
          operation: operation,
          requestId: event.requestId ?? requestId,
          expectedRevision: expectedRevision,
          submittedText: submittedText,
          targetTurnId: targetTurnId,
        );
        await _hydrate(event.sessionId, token: token);
        if (_isCurrent(token)) {
          final kind = state.turns.isEmpty
              ? ChatMessageKind.conversation
              : switch (state.turns.last.route) {
                  ConversationRoute.recommendation =>
                    ChatMessageKind.recommendation,
                  ConversationRoute.forkReroute => ChatMessageKind.forkReroute,
                  _ => ChatMessageKind.conversation,
                };
          state = state.copyWith(
            activity: ChatActivity.turnFailed,
            error: appError,
            activeTurnId: null,
            activeAttemptId: null,
            messages: [
              ...state.messages,
              ChatMessage(
                id: 'failed-${event.attemptId}',
                role: ChatRole.assistant,
                content: message,
                createdAt: DateTime.now(),
                relatedRecommendations: const [],
                status: ChatMessageStatus.error,
                kind: kind,
              ),
            ],
          );
          _activeEventRevision = null;
        }
    }
  }

  Future<void> _hydrate(String sessionId, {required int token}) async {
    final result = await ref
        .read(conversationRepositoryProvider)
        .loadSession(sessionId);
    if (!_isCurrent(token)) return;
    switch (result) {
      case Success<ConversationAggregate>(:final data):
        _applyAggregate(data);
      case Failure<ConversationAggregate>(:final error):
        state = state.copyWith(
          activity: ChatActivity.loadFailed,
          error: error,
          messages: const [],
          turns: const [],
        );
    }
  }

  void _applyAggregate(ConversationAggregate aggregate) {
    final session = aggregate.session;
    final professor = session.professorId == null
        ? null
        : ref.read(mockDbProvider).getProfessor(session.professorId!);
    final anchor = session.kind == ConversationSessionKind.fork
        ? ForkRef(
            forkId: session.id,
            mainSessionId: session.rootSessionId,
            professorId: session.professorId ?? '',
            professorName: professor?.name ?? '该导师',
            university: professor?.university ?? '',
            college: professor?.college,
            createdAt: session.createdAt,
          )
        : null;
    final latestStatus = aggregate.turns.isEmpty
        ? null
        : aggregate.turns.last.status;
    final activity = switch (latestStatus) {
      ConversationTurnStatus.interrupted => ChatActivity.interrupted,
      ConversationTurnStatus.failed => ChatActivity.turnFailed,
      _ => ChatActivity.idle,
    };
    state = ChatState(
      sessionId: session.id,
      professorId: session.professorId,
      messages: aggregate.messages,
      activity: activity,
      followUpQuestions: state.followUpQuestions,
      forkAnchor: anchor,
      kind: session.kind,
      rootSessionId: session.rootSessionId,
      sourceSessionId: session.sourceSessionId,
      sourceTurnId: session.sourceTurnId,
      revision: session.revision,
      turns: aggregate.turns,
      legacyContextIncomplete: session.legacyContextIncomplete,
    );
  }

  List<ChatMessage> _mergeCompletedMessage(
    List<ChatMessage> messages,
    ChatMessage completed, {
    required String attemptId,
  }) {
    final completedRecommendations = completed.relatedRecommendations;
    final index = messages.indexWhere((message) => message.id == completed.id);
    if (index != -1) {
      final existing = messages[index];
      if (existing.relatedRecommendations.isNotEmpty ||
          completedRecommendations.isEmpty) {
        return messages;
      }
      final merged = [...messages];
      merged[index] = existing.copyWith(
        content: existing.content.isEmpty ? completed.content : existing.content,
        relatedRecommendations: completedRecommendations,
        kind: completed.kind,
        status: existing.status == ChatMessageStatus.done
            ? existing.status
            : completed.status,
      );
      return merged;
    }

    final pendingIndex = messages.indexWhere(
      (message) => message.id == 'pending-$attemptId',
    );
    if (pendingIndex != -1) {
      final merged = [...messages];
      merged[pendingIndex] = completed;
      return merged;
    }

    if (completedRecommendations.isEmpty) return messages;
    return [...messages, completed];
  }

  String? _latestRecommendationTurn(
    ConversationAggregate aggregate,
    String professorId,
  ) {
    for (var i = aggregate.messages.length - 1; i >= 0; i--) {
      final message = aggregate.messages[i];
      if (message.kind != ChatMessageKind.recommendation ||
          !message.relatedRecommendations.any(
            (r) => r.professorId == professorId,
          )) {
        continue;
      }
      var turnIndex = -1;
      for (var j = 0; j <= i; j++) {
        if (aggregate.messages[j].role == ChatRole.user) turnIndex++;
      }
      if (turnIndex >= 0 && turnIndex < aggregate.turns.length) {
        return aggregate.turns[turnIndex].id;
      }
    }
    return null;
  }

  Future<void> _cancelIterator() async {
    final iterator = _iterator;
    _iterator = null;
    if (iterator != null) await iterator.cancel();
  }

  Future<void> _regenerateLatest() async {
    if (!state.canRegenerate || state.sessionId == null) return;
    final turn = state.turns.last;
    final sessionId = state.sessionId!;
    final requestId = _ids.generate();
    final expectedRevision = state.revision;
    final messages = [...state.messages];
    if (messages.isNotEmpty && messages.last.role == ChatRole.assistant) {
      messages.removeLast();
    }
    final activity = switch (turn.route) {
      null => ChatActivity.classifying,
      ConversationRoute.recommendation => ChatActivity.recommending,
      ConversationRoute.forkReroute => ChatActivity.committing,
      ConversationRoute.conversation => ChatActivity.connecting,
    };
    state = state.copyWith(activity: activity, messages: messages, error: null);
    await _runEvents(
      ref
          .read(conversationRepositoryProvider)
          .regenerateTurn(
            sessionId: sessionId,
            turnId: turn.id,
            expectedRevision: expectedRevision,
            requestId: requestId,
          ),
      sessionId: sessionId,
      operation: 'regenerateTurn',
      requestId: requestId,
      expectedRevision: expectedRevision,
      submittedText: turn.userMessage.content,
      targetTurnId: turn.id,
    );
  }

  Future<void> _persistFeedback(
    String messageId,
    ChatMessageFeedback previous,
    ChatMessageFeedback requested,
  ) async {
    final result = await ref
        .read(conversationRepositoryProvider)
        .setMessageFeedback(messageId, requested);
    if (!ref.mounted) return;
    if (result is Success<void>) return;
    final messages = [...state.messages];
    final index = messages.indexWhere((message) => message.id == messageId);
    if (index == -1 || messages[index].feedback != requested) return;
    messages[index] = messages[index].copyWith(feedback: previous);
    state = state.copyWith(
      messages: messages,
      error: result is Failure<void> ? result.error : const UnknownException(),
    );
    ref
        .read(apiErrorReporterProvider.notifier)
        .report('消息反馈同步失败', state.error!);
  }

  AppException _withChatContext(
    AppException error, {
    required String operation,
    required String requestId,
    required int expectedRevision,
    String? submittedText,
    String? targetTurnId,
  }) {
    final existing = error.diagnostics;
    return error.withDiagnostics(
      ErrorDiagnostics(
        requestId: existing?.requestId == null ? requestId : null,
        method: existing?.method == null ? 'POST' : null,
        context: _chatDebugContext(
          operation: operation,
          requestId: requestId,
          expectedRevision: expectedRevision,
          submittedText: submittedText,
          targetTurnId: targetTurnId,
        ),
      ),
    );
  }

  Map<String, String> _chatDebugContext({
    required String operation,
    required String requestId,
    required int expectedRevision,
    String? submittedText,
    String? targetTurnId,
  }) {
    final latestTurn = state.turns.lastOrNull;
    final latestMessage = state.messages.lastOrNull;
    final latestUserMessage = state.messages
        .where((message) => message.role == ChatRole.user)
        .lastOrNull;
    return {
      '操作': operation,
      '请求 ID': requestId,
      '会话 ID': ?state.sessionId,
      '导师 ID': ?state.professorId,
      '会话类型': state.kind.name,
      '当前活动': state.activity.name,
      '当前 revision': state.revision.toString(),
      '期望 revision': expectedRevision.toString(),
      '目标轮次 ID': ?targetTurnId,
      '活动轮次 ID': ?state.activeTurnId,
      '活动尝试 ID': ?state.activeAttemptId,
      '事件 revision 基线': ?_activeEventRevision?.toString(),
      '消息数': state.messages.length.toString(),
      '轮次数': state.turns.length.toString(),
      '最近轮次 ID': ?latestTurn?.id,
      '最近轮次状态': ?latestTurn?.status.name,
      '最近轮次路由': ?latestTurn?.route?.name,
      '最近轮次尝试 ID': ?latestTurn?.activeAttemptId,
      '最后消息 ID': ?latestMessage?.id,
      '最后消息角色': ?latestMessage?.role.name,
      '最后消息状态': ?latestMessage?.status.name,
      '最后消息类型': ?latestMessage?.kind.name,
      '最后消息长度': ?latestMessage?.content.length.toString(),
      '最近用户消息 ID': ?latestUserMessage?.id,
      '最近用户消息长度': ?latestUserMessage?.content.length.toString(),
      '最近用户消息摘要': ?_safeTextSummary(latestUserMessage?.content),
      '提交文本长度': ?submittedText?.length.toString(),
      '提交文本摘要': ?_safeTextSummary(submittedText),
    };
  }

  String? _safeTextSummary(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    var redacted = normalized
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]{8,}'), 'sk-[REDACTED]')
        .replaceAllMapped(
          RegExp(
            r'\b(api[_-]?key|authorization|cookie|token)\s*[:=]\s*\S+',
            caseSensitive: false,
          ),
          (match) => '${match.group(1)}=[REDACTED]',
        );
    const maxSummaryLength = 160;
    if (redacted.length <= maxSummaryLength) return redacted;
    return '${redacted.substring(0, maxSummaryLength)}…（已截断）';
  }

  bool _acceptEvent(ConversationEvent event, String sessionId) {
    if (event.sessionId != sessionId) {
      return false;
    }
    if (event is ConversationAcknowledged) {
      if (state.activeTurnId != null || state.activeAttemptId != null) {
        return false;
      }
      if (event.revision != state.revision &&
          event.revision != state.revision + 1) {
        return false;
      }
      return true;
    }
    if (state.activeTurnId == null || state.activeAttemptId == null) {
      throw const ValidationException('会话事件缺少 ack');
    }
    if (event.turnId != state.activeTurnId ||
        event.attemptId != state.activeAttemptId) {
      return false;
    }
    final pendingAssistantId = 'pending-${event.attemptId}';
    final hasPendingAssistant = state.messages.any(
      (message) => message.id == pendingAssistantId,
    );
    if (event is ConversationRouted && hasPendingAssistant) {
      return false;
    }
    if ((event is ConversationDelta || event is ConversationCompleted) &&
        !hasPendingAssistant) {
      throw const ValidationException('生成事件早于路由事件');
    }
    final baseRevision = _activeEventRevision;
    if (baseRevision == null) {
      throw const ValidationException('会话事件缺少 revision 基线');
    }
    if (event is ConversationCompleted) {
      final validRevision =
          event.revision == baseRevision || event.revision == baseRevision + 1;
      if (!validRevision ||
          event.session.id != sessionId ||
          event.session.revision != event.revision) {
        return false;
      }
      return true;
    }
    if (event is ConversationFailed) {
      if (event.revision != baseRevision &&
          event.revision != baseRevision + 1) {
        return false;
      }
      return true;
    }
    if (event.revision != baseRevision) {
      return false;
    }
    return true;
  }

  int _beginOperation() {
    _activeEventRevision = null;
    return ++_operation;
  }

  bool _isCurrent(int token) => token == _operation;
}

final chatProvider = NotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, Object>((_) => ChatNotifier());
