import '../../core/ids/uuid_v7.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_aggregate.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/conversation_turn.dart';

const conversationLocalOwnerId = 'local';

class ConversationCheckpoint {
  const ConversationCheckpoint({
    required this.id,
    required this.sessionId,
    required this.throughTurnId,
    required this.summary,
    required this.modelVersion,
    required this.createdAt,
    this.factsJson = '{}',
  });

  final String id;
  final String sessionId;
  final String throughTurnId;
  final String summary;
  final String factsJson;
  final String modelVersion;
  final DateTime createdAt;
}

abstract interface class ConversationStore {
  UuidV7 get ids;

  Future<ConversationSession> createSession({
    String? professorId,
    String ownerId = conversationLocalOwnerId,
    String? preferredId,
    String? title,
    bool legacyContextIncomplete = false,
  });

  Future<ConversationSession?> getSession(String rawId);

  Future<ConversationAggregate?> loadAggregate(
    String rawId, {
    bool includeInherited = false,
  });

  Future<ConversationSession> forkAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
    String ownerId = conversationLocalOwnerId,
  });

  Future<({ConversationTurn turn, AssistantAttempt attempt})> beginTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  });

  Future<void> setTurnPhase(
    String turnId,
    ConversationTurnStatus status, {
    ConversationRoute? route,
  });

  Future<AssistantAttempt> beginRegeneration({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  });

  Future<void> interruptAttempt(String attemptId, {String partial = ''});

  Future<ChatMessage> completeAttempt({
    required String sessionId,
    required String turnId,
    required String attemptId,
    required ChatMessage message,
  });

  Future<void> failAttempt({
    required String turnId,
    required String attemptId,
    String? errorCode,
    bool interrupted = false,
  });

  Future<void> setFeedback(String messageId, ChatMessageFeedback feedback);

  Future<List<ConversationSession>> listSessions({bool rootsOnly = true});

  Future<List<ConversationSession>> listForks(String rootSessionId);

  Future<void> deleteSession(String rawId);

  Future<void> clearSessions();

  Future<ConversationCheckpoint?> latestCheckpoint(String sessionId);

  Future<void> saveCheckpoint({
    required String sessionId,
    required String throughTurnId,
    required String summary,
    required String modelVersion,
    String factsJson = '{}',
  });
}
