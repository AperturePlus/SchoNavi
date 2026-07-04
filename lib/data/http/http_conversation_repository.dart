import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/error/app_exception.dart';
import '../../core/error/error_diagnostics.dart';
import '../../core/ids/uuid_v7.dart';
import '../../core/result/result.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/conversation_aggregate.dart';
import '../../domain/entities/conversation_event.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/conversation_turn.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../dto/api_envelope.dart';
import '../dto/chat_message_dto.dart';

class HttpConversationRepository implements ConversationRepository {
  HttpConversationRepository(this._dio, {UuidV7? ids}) : _ids = ids ?? UuidV7();

  final Dio _dio;
  final UuidV7 _ids;

  @override
  Future<Result<ConversationSession>> createSession({String? professorId}) {
    return guardApi(
      () async => _dio.post<dynamic>(
        '/api/v1/chat/sessions',
        data: {
          'kind': professorId == null ? 'general' : 'professor',
          'professor_id': ?professorId,
        },
      ),
      (data) => _session(asJsonObject(data)),
    );
  }

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) {
    return guardApi(
      () async => _dio.get<dynamic>('/api/v1/chat/sessions/$sessionId'),
      (data) {
        final json = asJsonObject(data);
        final sessionJson = json['session'];
        final session = _session(
          sessionJson is Map<String, dynamic> ? sessionJson : json,
        );
        final rawTurns = (json['turns'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
        final visibleTurns = session.isFork
            ? rawTurns
                  .where((turn) => turn['session_id']?.toString() == session.id)
                  .toList(growable: false)
            : rawTurns;
        final visibleTurnIds = visibleTurns
            .map((turn) => turn['id']?.toString())
            .whereType<String>()
            .toSet();
        final rawMessages = (json['messages'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item));
        final messages =
            (session.isFork
                    ? rawMessages.where(
                        (message) => visibleTurnIds.contains(
                          message['turn_id']?.toString(),
                        ),
                      )
                    : rawMessages)
                .map((m) => _message(m, m['id']?.toString() ?? _ids.generate()))
                .toList(growable: false);
        final turns = visibleTurns
            .map((turn) => _turn(turn, messages))
            .toList(growable: false);
        return ConversationAggregate(
          session: session,
          turns: turns,
          messages: messages,
        );
      },
    );
  }

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) {
    return guardApi(
      () async => _dio.post<dynamic>(
        '/api/v1/chat/sessions/$sourceSessionId/forks',
        data: {'source_turn_id': sourceTurnId, 'professor_id': professorId},
      ),
      (data) => _session(asJsonObject(data)),
    );
  }

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) {
    final resolvedRequestId = requestId ?? _ids.generate();
    return _eventStream(
      '/api/v1/chat/sessions/$sessionId/turns',
      data: {
        'text': text,
        'request_id': resolvedRequestId,
        'expected_revision': expectedRevision,
      },
      requestId: resolvedRequestId,
    );
  }

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) {
    final resolvedRequestId = requestId ?? _ids.generate();
    return _eventStream(
      '/api/v1/chat/turns/$turnId/attempts',
      data: {
        'session_id': sessionId,
        'request_id': resolvedRequestId,
        'expected_revision': expectedRevision,
      },
      requestId: resolvedRequestId,
    );
  }

  @override
  Future<Result<void>> cancelAttempt(String attemptId) => guardApi(
    () async => _dio.post<dynamic>('/api/v1/chat/attempts/$attemptId/cancel'),
    (_) {},
  );

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) => guardApi(
    () async => _dio.patch<dynamic>(
      '/api/v1/chat/messages/$messageId/feedback',
      data: {'feedback': feedback.name},
    ),
    (_) {},
  );

  @override
  Future<Result<List<ConversationSession>>> listSessions() =>
      guardApi(() async => _dio.get<dynamic>('/api/v1/chat/sessions'), (data) {
        final items = data is List
            ? data
            : (asJsonObject(data)['items'] as List<dynamic>? ?? const []);
        return items
            .whereType<Map>()
            .map((e) => _session(Map<String, dynamic>.from(e)))
            .toList(growable: false);
      });

  @override
  Future<Result<List<ConversationSession>>> listForks(String rootSessionId) =>
      guardApi(
        () async =>
            _dio.get<dynamic>('/api/v1/chat/sessions/$rootSessionId/forks'),
        (data) {
          final items = data is List
              ? data
              : (asJsonObject(data)['items'] as List<dynamic>? ?? const []);
          return items
              .whereType<Map>()
              .map((e) => _session(Map<String, dynamic>.from(e)))
              .toList(growable: false);
        },
      );

  @override
  Future<Result<void>> deleteSession(String sessionId) => guardApi(
    () async => _dio.delete<dynamic>('/api/v1/chat/sessions/$sessionId'),
    (_) {},
  );

  Stream<ConversationEvent> _eventStream(
    String path, {
    required Map<String, dynamic> data,
    required String requestId,
  }) async* {
    try {
      final response = await _dio.post<ResponseBody>(
        path,
        data: data,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Accept': 'text/event-stream',
            'Idempotency-Key': requestId,
          },
        ),
      );
      final body = response.data;
      if (body == null) throw const ServerException();
      var eventName = 'message';
      final dataLines = <String>[];

      ConversationEvent? decodeEvent() {
        if (dataLines.isEmpty) return null;
        final decoded = jsonDecode(dataLines.join('\n'));
        dataLines.clear();
        if (decoded is! Map) return null;
        final json = Map<String, dynamic>.from(decoded);
        final sessionId = json['session_id']?.toString() ?? '';
        final turnId = json['turn_id']?.toString() ?? '';
        final attemptId = json['attempt_id']?.toString() ?? '';
        final revision = (json['revision'] as num?)?.toInt() ?? 0;
        return switch (eventName) {
          'ack' => ConversationAcknowledged(
            sessionId: sessionId,
            turnId: turnId,
            attemptId: attemptId,
            revision: revision,
          ),
          'route' => ConversationRouted(
            sessionId: sessionId,
            turnId: turnId,
            attemptId: attemptId,
            revision: revision,
            route: _enumByName(
              ConversationRoute.values,
              json['route']?.toString() ?? 'conversation',
              'route',
            ),
          ),
          'delta' => ConversationDelta(
            sessionId: sessionId,
            turnId: turnId,
            attemptId: attemptId,
            revision: revision,
            text: json['text']?.toString() ?? '',
          ),
          'completed' => _completedEvent(
            sessionId: sessionId,
            turnId: turnId,
            attemptId: attemptId,
            revision: revision,
            json: json,
          ),
          'error' => ConversationFailed(
            sessionId: sessionId,
            turnId: turnId,
            attemptId: attemptId,
            revision: revision,
            message: json['message']?.toString() ?? '服务异常，请稍后重试',
            code: json['code']?.toString(),
            requestId: requestId,
            path: path,
          ),
          _ => null,
        };
      }

      final lines = body.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.startsWith('event:')) {
          eventName = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          dataLines.add(line.substring(5).trimLeft());
        } else if (line.isEmpty) {
          final event = decodeEvent();
          if (event != null) yield event;
          eventName = 'message';
        }
      }
      final tail = decodeEvent();
      if (tail != null) yield tail;
    } on AppException {
      rethrow;
    } on DioException catch (error) {
      throw await mapDioExceptionWithResponsePreview(error);
    } on FormatException catch (error) {
      final detail = error.message.isEmpty ? '响应结构不符合契约' : error.message;
      throw ValidationException(
        '服务返回格式异常：$detail',
        diagnostics: ErrorDiagnostics(
          requestId: requestId,
          method: 'POST',
          path: path,
          exceptionType: error.runtimeType.toString(),
          cause: detail,
          occurredAt: DateTime.now(),
        ),
      );
    } catch (error, stackTrace) {
      throw normalizeAppException(error, stackTrace).withDiagnostics(
        ErrorDiagnostics(
          requestId: requestId,
          method: 'POST',
          path: path,
          occurredAt: DateTime.now(),
        ),
      );
    }
  }

  ConversationSession _session(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? json['session_id']?.toString() ?? '';
    return ConversationSession(
      id: id,
      kind: _enumByName(
        ConversationSessionKind.values,
        json['kind']?.toString() ?? 'general',
        'kind',
      ),
      rootSessionId: json['root_session_id']?.toString() ?? id,
      sourceSessionId: json['source_session_id']?.toString(),
      sourceTurnId: json['source_turn_id']?.toString(),
      professorId: json['professor_id']?.toString(),
      ownerId: json['owner_id']?.toString() ?? 'remote',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString(),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
      updatedAt: _requiredDateTime(json['updated_at'], 'updated_at'),
      deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
      legacyContextIncomplete: json['legacy_context_incomplete'] == true,
    );
  }

  ConversationTurn _turn(
    Map<String, dynamic> json,
    List<ChatMessage> messages,
  ) {
    final userId = json['user_message_id']?.toString() ?? '';
    final user =
        messages.where((m) => m.id == userId).firstOrNull ??
        ChatMessage(
          id: userId,
          role: ChatRole.user,
          content: json['user_text']?.toString() ?? '',
          createdAt: DateTime.now(),
          relatedRecommendations: const [],
          status: ChatMessageStatus.done,
        );
    return ConversationTurn(
      id: json['id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? '',
      ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
      status: _enumByName(
        ConversationTurnStatus.values,
        json['status']?.toString() ?? 'interrupted',
        'status',
      ),
      route: json['route'] == null
          ? null
          : _enumByName(
              ConversationRoute.values,
              json['route'].toString(),
              'route',
            ),
      userMessage: user,
      activeAttemptId: json['active_attempt_id']?.toString(),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
      updatedAt: _requiredDateTime(json['updated_at'], 'updated_at'),
    );
  }

  ConversationCompleted _completedEvent({
    required String sessionId,
    required String turnId,
    required String attemptId,
    required int revision,
    required Map<String, dynamic> json,
  }) {
    final messageJson = asJsonObject(json['message']);
    return ConversationCompleted(
      sessionId: sessionId,
      turnId: turnId,
      attemptId: attemptId,
      revision: revision,
      message: _message(messageJson, messageJson['id']?.toString() ?? ''),
      session: _session(asJsonObject(json['session'])),
      quickActions: (json['quick_actions'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
    );
  }

  ChatMessage _message(Map<String, dynamic> json, String fallbackId) {
    _requiredDateTime(json['created_at'], 'message.created_at');
    return ChatMessageDto.fromJson(json).toEntity(fallbackId);
  }

  T _enumByName<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('unknown $field: $name');
  }

  DateTime _requiredDateTime(Object? value, String field) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) {
      throw FormatException('missing $field');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) throw FormatException('invalid $field: $raw');
    return parsed;
  }
}
