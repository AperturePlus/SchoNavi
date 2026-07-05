import '../../core/result/result.dart';
import '../entities/chat_message.dart';
import '../entities/conversation_aggregate.dart';
import '../entities/conversation_event.dart';
import '../entities/conversation_session.dart';

abstract interface class ConversationRepository {
  Future<Result<ConversationSession>> createSession({String? professorId});

  Future<Result<ConversationAggregate>> loadSession(String sessionId);

  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  });

  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  });

  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  });

  Future<Result<void>> cancelAttempt(String attemptId);

  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  );

  Future<Result<List<ConversationSession>>> listSessions();

  Future<Result<List<ConversationSession>>> listForks(String rootSessionId);

  Future<Result<void>> deleteSession(String sessionId);

  Future<Result<void>> clearSessions();
}
