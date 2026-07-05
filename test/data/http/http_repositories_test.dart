import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/http/http_chat_repository.dart';
import 'package:scho_navi/data/http/http_conversation_repository.dart';
import 'package:scho_navi/data/http/http_favorite_repository.dart';
import 'package:scho_navi/data/http/http_history_repository.dart';
import 'package:scho_navi/data/http/http_professor_repository.dart';
import 'package:scho_navi/data/http/http_profile_repository.dart';
import 'package:scho_navi/data/http/http_recommendation_repository.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/favorite_item.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}

void main() {
  test('AppConfig resolves HTTP mode from API_BASE_URL', () {
    final cfg = AppConfig.resolve(
      apiKey: 'sk-test',
      apiBaseUrl: 'https://api.example.com/',
    );

    expect(cfg.dataSource, DataSource.http);
    expect(cfg.api.baseUrl, 'https://api.example.com');
    expect(cfg.llm.apiKey, 'sk-test');
  });

  test(
    'HttpRecommendationRepository posts contract request and decodes envelope',
    () async {
      RequestOptions? captured;
      final repo = HttpRecommendationRepository(
        _dio((options) async {
          captured = options;
          return _jsonFixture('mentor_recommendation_success.json');
        }),
      );

      final result = await repo.getRecommendations(prompt: '医学影像');

      expect(captured!.path, '/api/v1/recommendations/mentors');
      expect(captured!.method, 'POST');
      expect((captured!.data as Map)['prompt'], '医学影像');
      final data = (result as Success).data;
      expect(data.sessionId, 's_123');
      expect(data.recommendations.single.professorId, 'p_001');
    },
  );

  test('HttpProfessorRepository decodes professor envelope', () async {
    final repo = HttpProfessorRepository(
      _dio((_) async => _jsonFixture('professor_success.json')),
    );

    final result = await repo.getProfessor('p_001');

    final professor = (result as Success).data;
    expect(professor.id, 'p_001');
    expect(professor.dataQualityScore, 0.87);
  });

  test('non-zero envelope maps to Failure with backend message', () async {
    final repo = HttpRecommendationRepository(
      _dio((_) async => _jsonFixture('envelope_error.json')),
    );

    final result = await repo.getRecommendations(prompt: ' ');

    expect(result, isA<Failure>());
    expect((result as Failure).error.message, '输入内容不合法');
  });

  test('Dio timeout maps to TimeoutException', () async {
    final repo = HttpProfessorRepository(
      _dio((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }),
    );

    final result = await repo.getProfessor('p_001');

    expect((result as Failure).error, isA<TimeoutException>());
  });

  test('malformed success data maps to ServerException failure', () async {
    final repo = HttpProfessorRepository(
      _dio(
        (_) async => _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {'bad': true},
          }),
        ),
      ),
    );

    final result = await repo.getProfessor('p_001');

    expect((result as Failure).error, isA<ServerException>());
  });

  test('HttpChatRepository parses contract SSE deltas', () async {
    RequestOptions? captured;
    final repo = HttpChatRepository(
      _dio((options) async {
        captured = options;
        return _sseBody([
          'event: delta\ndata: {"text":"你"}\n\n',
          'event: delta\ndata: {"text":"好"}\n\n',
          'event: done\ndata: {"session_id":"s_123"}\n\n',
        ]);
      }),
    );

    final deltas = await repo
        .streamReply(sessionId: 's_123', message: 'hi', professorId: 'p_001')
        .toList();

    expect(captured!.path, '/api/v1/chat/stream');
    expect(captured!.queryParameters['professor_id'], 'p_001');
    expect(captured!.headers['X-Request-ID'], isNotEmpty);
    expect(deltas, ['你', '好']);
  });

  test('HttpChatRepository keeps SSE error diagnostics', () async {
    RequestOptions? captured;
    final repo = HttpChatRepository(
      _dio((options) async {
        captured = options;
        return _sseBody(
          [
            'event: error\n'
                'data: {"code":"CHAT_BLOCKED","message":"输入内容不合法"}\n\n',
          ],
          requestId: 'server-request-id',
        );
      }),
    );

    await expectLater(
      repo.streamReply(sessionId: 's_123', message: 'bad').toList(),
      throwsA(
        isA<ValidationException>()
            .having((error) => error.message, 'message', '输入内容不合法')
            .having(
              (error) => error.diagnostics?.requestId,
              'requestId',
              'server-request-id',
            )
            .having(
              (error) => error.diagnostics?.method,
              'method',
              'GET',
            )
            .having(
              (error) => error.diagnostics?.path,
              'path',
              '/api/v1/chat/stream',
            )
            .having(
              (error) => error.diagnostics?.backendCode,
              'backendCode',
              'CHAT_BLOCKED',
            )
            .having(
              (error) => error.diagnostics?.backendMessage,
              'backendMessage',
              '输入内容不合法',
            )
            .having(
              (error) => error.diagnostics?.exceptionType,
              'exceptionType',
              'ChatStreamException',
            ),
      ),
    );
    expect(captured!.headers['X-Request-ID'], isNotEmpty);
  });

  test('HttpChatRepository keeps malformed SSE diagnostics', () async {
    final repo = HttpChatRepository(
      _dio((_) async => _sseBody(['event: delta\ndata: not-json\n\n'])),
    );

    await expectLater(
      repo.streamReply(sessionId: 's_123', message: 'hi').toList(),
      throwsA(
        isA<ValidationException>()
            .having(
              (error) => error.message,
              'message',
              contains('服务返回格式异常'),
            )
            .having(
              (error) => error.diagnostics?.requestId,
              'requestId',
              isNotEmpty,
            )
            .having(
              (error) => error.diagnostics?.path,
              'path',
              '/api/v1/chat/stream',
            )
            .having(
              (error) => error.diagnostics?.cause,
              'cause',
              contains('Unexpected character'),
            ),
      ),
    );
  });

  test('HttpChatRepository maps SSE Dio timeout with request diagnostics', () async {
    final repo = HttpChatRepository(
      _dio((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      }),
    );

    await expectLater(
      repo.streamReply(sessionId: 's_123', message: 'hi').toList(),
      throwsA(
        isA<TimeoutException>()
            .having(
              (error) => error.diagnostics?.requestId,
              'requestId',
              isNotEmpty,
            )
            .having(
              (error) => error.diagnostics?.path,
              'path',
              '/api/v1/chat/stream',
            ),
      ),
    );
  });

  test(
    'HttpConversationRepository hides inherited fork turns from old backend',
    () async {
      final repo = HttpConversationRepository(
        _dio(
          (_) async => _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'session': {
                  'id': 'fork-1',
                  'kind': 'fork',
                  'root_session_id': 'main-1',
                  'source_session_id': 'main-1',
                  'source_turn_id': 'source-turn',
                  'professor_id': 'p_001',
                  'revision': 1,
                  'created_at': '2026-06-28T10:00:00.000Z',
                  'updated_at': '2026-06-28T10:00:00.000Z',
                },
                'turns': [
                  {
                    'id': 'source-turn',
                    'session_id': 'main-1',
                    'ordinal': 0,
                    'status': 'completed',
                    'user_message_id': 'source-user',
                    'created_at': '2026-06-28T10:00:00.000Z',
                    'updated_at': '2026-06-28T10:00:00.000Z',
                  },
                  {
                    'id': 'fork-turn',
                    'session_id': 'fork-1',
                    'ordinal': 0,
                    'status': 'completed',
                    'user_message_id': 'fork-user',
                    'created_at': '2026-06-28T10:01:00.000Z',
                    'updated_at': '2026-06-28T10:01:00.000Z',
                  },
                ],
                'messages': [
                  _conversationMessageJson(
                    id: 'source-user',
                    turnId: 'source-turn',
                    role: 'user',
                    content: '推荐计算机视觉导师',
                  ),
                  _conversationMessageJson(
                    id: 'source-assistant',
                    turnId: 'source-turn',
                    role: 'assistant',
                    content: '为你推荐张三',
                  ),
                  _conversationMessageJson(
                    id: 'fork-user',
                    turnId: 'fork-turn',
                    role: 'user',
                    content: '张三为什么适合我',
                  ),
                  _conversationMessageJson(
                    id: 'fork-assistant',
                    turnId: 'fork-turn',
                    role: 'assistant',
                    content: '因为研究方向匹配',
                  ),
                ],
              },
            }),
          ),
        ),
      );

      final result = await repo.loadSession('fork-1');

      final aggregate = (result as Success).data;
      expect(aggregate.turns.map((turn) => turn.id), ['fork-turn']);
      expect(aggregate.messages.map((message) => message.content), [
        '张三为什么适合我',
        '因为研究方向匹配',
      ]);
    },
  );

  test('HttpConversationRepository sends matching idempotency key', () async {
    RequestOptions? captured;
    final repo = HttpConversationRepository(
      _dio((options) async {
        captured = options;
        return _sseBody([
          'event: ack\n'
              'data: {"session_id":"s_123","turn_id":"t_1","attempt_id":"a_1","revision":3}\n\n',
        ]);
      }),
    );

    final events = await repo
        .submitTurn(
          sessionId: 's_123',
          text: 'hello',
          expectedRevision: 3,
          requestId: '0197b763-8a74-7000-8000-000000000001',
        )
        .toList();

    expect(events, hasLength(1));
    expect(
      captured!.headers['Idempotency-Key'],
      '0197b763-8a74-7000-8000-000000000001',
    );
    expect(
      (captured!.data as Map)['request_id'],
      captured!.headers['Idempotency-Key'],
    );
  });

  test('HttpConversationRepository clears all sessions with bulk delete', () async {
    RequestOptions? captured;
    final repo = HttpConversationRepository(
      _dio((options) async {
        captured = options;
        return _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {'deleted': true, 'deleted_count': 21},
          }),
        );
      }),
    );

    final result = await repo.clearSessions();

    expect(result, isA<Success<void>>());
    expect(captured!.path, '/api/v1/chat/sessions');
    expect(captured!.method, 'DELETE');
  });

  test(
    'HttpConversationRepository rejects malformed completed SSE payload',
    () async {
      final repo = HttpConversationRepository(
        _dio((_) async {
          return _sseBody([
            'event: completed\n'
                'data: {"session_id":"s_123","turn_id":"t_1","attempt_id":"a_1","revision":4}\n\n',
          ]);
        }),
      );

      await expectLater(
        repo
            .submitTurn(sessionId: 's_123', text: 'hello', expectedRevision: 3)
            .toList(),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.message,
            'message',
            contains('服务返回格式异常'),
          ),
        ),
      );
    },
  );

  test(
    'HttpChatRepository does not synthesize missing fork createdAt',
    () async {
      final repo = HttpChatRepository(
        _dio(
          (_) async => _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'items': [
                  {
                    'id': 'fork-1',
                    'root_session_id': 's_123',
                    'professor_id': 'p_001',
                  },
                ],
              },
            }),
          ),
        ),
      );

      final result = await repo.listForks(mainSessionId: 's_123');

      expect((result as Failure).error, isA<ServerException>());
    },
  );

  test('HttpHistoryRepository lists search history from envelope', () async {
    RequestOptions? captured;
    final repo = HttpHistoryRepository(
      _dio((options) async {
        captured = options;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': [_historyJson('s_1')],
          }),
        );
      }),
    );

    final emitted = await repo.watch().skip(1).first;

    expect(captured!.path, '/api/v1/history');
    expect(captured!.method, 'GET');
    expect(emitted.single.sessionId, 's_1');
    expect(emitted.single.type, SearchHistoryType.mentor);
  });

  test('HttpHistoryRepository posts generated search history item', () async {
    RequestOptions? captured;
    final repo = HttpHistoryRepository(
      _dio((options) async {
        captured = options;
        return _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': _historyJson('s_123'),
          }),
        );
      }),
      now: () => DateTime.utc(2026, 6, 15, 10),
    );

    await repo.addFromResult(
      prompt: '医学影像 上海',
      result: _recommendationResult(),
    );

    expect(captured!.path, '/api/v1/history');
    expect(captured!.method, 'POST');
    expect(captured!.data, {
      'type': 'mentor',
      'session_id': 's_123',
      'prompt': '医学影像 上海',
      'created_at': '2026-06-15T10:00:00.000Z',
      'summary': '方向：医学影像 / 地区：上海',
      'research_interests': ['医学影像'],
      'preferred_locations': ['上海'],
      'recommendation_count': 1,
    });
  });

  test('HttpHistoryRepository posts competition_result for competition history', () async {
    RequestOptions? captured;
    final repo = HttpHistoryRepository(
      _dio((options) async {
        captured = options;
        return _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': _competitionHistoryJson(),
          }),
        );
      }),
      now: () => DateTime.utc(2026, 6, 15, 10),
    );

    await repo.addFromCompetitionResult(
      prompt: '数学建模 团队赛',
      result: _competitionResult(),
    );

    expect(captured!.path, '/api/v1/history');
    expect(captured!.method, 'POST');
    final data = captured!.data as Map;
    expect(data['type'], 'competition');
    expect(data['session_id'], 'c_123');
    expect(data['competition_result'], _competitionResultJson());
  });

  test('HttpHistoryRepository fetches one competition history item', () async {
    final captured = <RequestOptions>[];
    final repo = HttpHistoryRepository(
      _dio((options) async {
        captured.add(options);
        return _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': _competitionHistoryJson(),
          }),
        );
      }),
    );

    final item = await repo.getBySessionId(
      'c_123',
      type: SearchHistoryType.competition,
    );

    expect(captured.single.path, '/api/v1/history/c_123');
    expect(captured.single.queryParameters['type'], 'competition');
    expect(item?.competitionResult?.recommendations.single.name, '全国大学生数学建模竞赛');
    expect(repo.list().single.sessionId, 'c_123');
  });

  test(
    'HttpProfileRepository does not update snapshot when save fails',
    () async {
      final repo = HttpProfileRepository(
        _dio(
          (_) async => _jsonString(
            jsonEncode({'code': 40001, 'message': '输入内容不合法', 'data': null}),
          ),
        ),
      );

      await expectLater(
        repo.save(const UserProfile(name: '张三')),
        throwsA(isA<ValidationException>()),
      );

      expect(repo.load().isEmpty, isTrue);
    },
  );

  test('HttpProfileRepository refresh treats null data as empty profile', () async {
    final repo = HttpProfileRepository(
      _dio(
        (_) async => _jsonString(
          jsonEncode({'code': 0, 'message': 'ok', 'data': null}),
        ),
      ),
    );

    final profile = await repo.refresh();

    expect(profile.isEmpty, isTrue);
    expect(repo.load().isEmpty, isTrue);
  });

  test('HttpProfileRepository refresh maps object data to snapshot', () async {
    final repo = HttpProfileRepository(
      _dio(
        (_) async => _jsonString(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {
              'name': '张三',
              'school': '清华大学',
              'major': '计算机科学',
              'research_interests': ['人工智能'],
              'target_degree': '申请博士',
            },
          }),
        ),
      ),
    );

    final profile = await repo.refresh();

    expect(profile.name, '张三');
    expect(profile.school, '清华大学');
    expect(profile.major, '计算机科学');
    expect(profile.researchInterests, ['人工智能']);
    expect(profile.targetDegree, '申请博士');
    expect(repo.load().name, '张三');
  });

  test(
    'HttpProfileRepository save still rejects null success data',
    () async {
      final repo = HttpProfileRepository(
        _dio((options) async {
          final data = options.method == 'GET'
              ? {
                  'name': '张三',
                  'school': '清华大学',
                }
              : null;
          return _jsonString(
            jsonEncode({'code': 0, 'message': 'ok', 'data': data}),
          );
        }),
      );
      await repo.refresh();

      await expectLater(
        repo.save(const UserProfile(name: '李四')),
        throwsA(isA<ServerException>()),
      );

      expect(repo.load().name, '张三');
    },
  );

  test(
    'HttpFavoriteRepository does not remove snapshot when delete fails',
    () async {
      var calls = 0;
      final repo = HttpFavoriteRepository(
        _dio((_) async {
          calls++;
          if (calls == 1) {
            return _jsonString(
              jsonEncode({
                'code': 0,
                'message': 'ok',
                'data': {'favorited': true, 'item': _favoriteJson('p_001')},
              }),
            );
          }
          return _jsonString(
            jsonEncode({'code': 50001, 'message': '服务异常，请稍后重试', 'data': null}),
          );
        }),
      );

      await repo.add(_favoriteItem('p_001'));
      await expectLater(
        repo.remove('p_001'),
        throwsA(isA<ValidationException>()),
      );

      expect(repo.list().map((item) => item.professorId), contains('p_001'));
    },
  );

  test('HttpHistoryRepository does not add snapshot when post fails', () async {
    final repo = HttpHistoryRepository(
      _dio(
        (_) async => _jsonString(
          jsonEncode({'code': 50001, 'message': '服务异常，请稍后重试', 'data': null}),
        ),
      ),
      now: () => DateTime.utc(2026, 6, 15, 10),
    );

    await expectLater(
      repo.addFromResult(prompt: '医学影像 上海', result: _recommendationResult()),
      throwsA(isA<ValidationException>()),
    );

    expect(repo.list(), isEmpty);
  });

  test(
    'HttpHistoryRepository deletes one item and clears all history',
    () async {
      final captured = <RequestOptions>[];
      final repo = HttpHistoryRepository(
        _dio((options) async {
          captured.add(options);
          return _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {'removed': true},
            }),
          );
        }),
      );

      await repo.remove('s_123');
      await repo.clear();

      expect(captured[0].path, '/api/v1/history/s_123');
      expect(captured[0].method, 'DELETE');
      expect(captured[1].path, '/api/v1/history');
      expect(captured[1].method, 'DELETE');
    },
  );
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handler) {
  return Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = _FakeAdapter(handler);
}

ResponseBody _jsonFixture(String name) {
  final text = File('test/fixtures/api/$name').readAsStringSync();
  return _jsonString(text);
}

ResponseBody _jsonString(String text) {
  return ResponseBody.fromString(
    text,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody _sseBody(List<String> events, {String? requestId}) {
  Stream<Uint8List> chunks() async* {
    for (final event in events) {
      yield Uint8List.fromList(utf8.encode(event));
    }
  }

  final headers = <String, List<String>>{
    Headers.contentTypeHeader: ['text/event-stream'],
    if (requestId != null) 'x-request-id': [requestId],
  };
  return ResponseBody(
    chunks(),
    200,
    headers: headers,
  );
}

Map<String, dynamic> _historyJson(String sessionId) => <String, dynamic>{
  'type': 'mentor',
  'session_id': sessionId,
  'prompt': '医学影像 上海',
  'created_at': '2026-06-15T10:00:00.000Z',
  'summary': '方向：医学影像 / 地区：上海',
  'research_interests': ['医学影像'],
  'preferred_locations': ['上海'],
  'recommendation_count': 1,
};

Map<String, dynamic> _competitionHistoryJson() => <String, dynamic>{
  'type': 'competition',
  'session_id': 'c_123',
  'prompt': '数学建模 团队赛',
  'created_at': '2026-06-15T10:00:00.000Z',
  'summary': '方向：数学建模 / 类别：理学类',
  'research_interests': ['数学建模', '理学类'],
  'preferred_locations': <String>[],
  'recommendation_count': 1,
  'competition_result': _competitionResultJson(),
};

Map<String, dynamic> _competitionResultJson() => <String, dynamic>{
  'session_id': 'c_123',
  'understanding': {
    'directions': ['数学建模'],
    'categories': ['理学类'],
    'timing_preferences': ['秋季/下半年'],
    'team_preferences': ['团队赛'],
    'uncertainties': <String>[],
  },
  'recommendations': [
    {
      'id': 'comp_math_modeling',
      'name': '全国大学生数学建模竞赛',
      'category': '理学类',
      'level': '国家级',
      'tags': ['数学建模', '团队赛'],
      'team_size': '3 人团队',
      'signup_time': '以官网通知为准',
      'contest_time': '通常每年 9 月',
      'format': '建模、编程和论文写作',
      'organizer': '中国工业与应用数学学会',
      'official_url': 'http://www.mcm.edu.cn/',
      'reason': '方向匹配。',
      'preparation_tips': ['训练论文写作'],
      'limitations': ['以官网通知为准。'],
      'match_score': 0.91,
    },
  ],
  'follow_up_questions': <String>[],
};

CompetitionRecommendationResult _competitionResult() =>
    const CompetitionRecommendationResult(
      sessionId: 'c_123',
      understanding: CompetitionQueryUnderstanding(
        directions: ['数学建模'],
        categories: ['理学类'],
        timingPreferences: ['秋季/下半年'],
        teamPreferences: ['团队赛'],
        uncertainties: [],
      ),
      recommendations: [
        RecommendedCompetition(
          id: 'comp_math_modeling',
          name: '全国大学生数学建模竞赛',
          category: '理学类',
          level: '国家级',
          tags: ['数学建模', '团队赛'],
          teamSize: '3 人团队',
          signupTime: '以官网通知为准',
          contestTime: '通常每年 9 月',
          format: '建模、编程和论文写作',
          organizer: '中国工业与应用数学学会',
          officialUrl: 'http://www.mcm.edu.cn/',
          reason: '方向匹配。',
          preparationTips: ['训练论文写作'],
          limitations: ['以官网通知为准。'],
          matchScore: 0.91,
        ),
      ],
      followUpQuestions: [],
    );

Map<String, dynamic> _favoriteJson(String professorId) => <String, dynamic>{
  'professor_id': professorId,
  'name': '张三',
  'university': '上海交通大学',
  'college': '电子信息与电气工程学院',
  'title': '教授',
  'research_fields': ['医学影像'],
  'homepage_url': 'https://example.edu.cn',
  'favorited_at': '2026-06-15T10:00:00.000Z',
};

FavoriteItem _favoriteItem(String professorId) => FavoriteItem(
  professorId: professorId,
  name: '张三',
  university: '上海交通大学',
  college: '电子信息与电气工程学院',
  title: '教授',
  researchFields: const ['医学影像'],
  homepageUrl: 'https://example.edu.cn',
  favoritedAt: DateTime.utc(2026, 6, 15, 10),
);

Map<String, dynamic> _conversationMessageJson({
  required String id,
  required String turnId,
  required String role,
  required String content,
}) => <String, dynamic>{
  'id': id,
  'turn_id': turnId,
  'role': role,
  'content': content,
  'created_at': '2026-06-28T10:00:00.000Z',
  'status': 'done',
  'kind': 'conversation',
  'feedback': 'none',
  'related_recommendations': <dynamic>[],
};

RecommendationResult _recommendationResult() => const RecommendationResult(
  sessionId: 's_123',
  queryUnderstanding: QueryUnderstanding(
    researchInterests: ['医学影像'],
    preferredLocations: ['上海'],
    preferredUniversities: [],
    uncertainties: [],
  ),
  recommendations: [
    Recommendation(
      professorId: 'p_001',
      name: '张三',
      university: '上海交通大学',
      college: '电子信息与电气工程学院',
      title: '教授',
      researchFields: ['医学影像'],
      matchLevel: MatchLevel.high,
      reason: '方向匹配。',
      limitations: ['以官网为准'],
    ),
  ],
  followUpQuestions: [],
);
