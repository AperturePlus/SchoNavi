import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/http/http_quick_actions_source.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/query_understanding.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';

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
  ) => handler(options);
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handler) {
  return Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = _FakeAdapter(handler);
}

ResponseBody _jsonString(String text) => ResponseBody.fromString(
  text,
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

ResponseBody _quickActionsEnvelope(List<String> actions) => _jsonString(
  jsonEncode({
    'code': 0,
    'message': 'ok',
    'data': {'quick_actions': actions},
  }),
);

RecommendationResult _resultWith(List<Recommendation> recs) {
  return RecommendationResult(
    sessionId: 's_1',
    queryUnderstanding: const QueryUnderstanding(
      researchInterests: ['计算机视觉'],
      preferredLocations: ['北京'],
      preferredUniversities: [],
      degreeStage: null,
      uncertainties: [],
    ),
    recommendations: recs,
    followUpQuestions: const [],
  );
}

const _rec = Recommendation(
  professorId: 'p_001',
  name: '张三',
  university: '清华大学',
  college: '计算机学院',
  title: '教授',
  researchFields: ['计算机视觉', '医学影像'],
  matchLevel: MatchLevel.high,
  reason: '方向契合',
  limitations: [],
);

void main() {
  group('HttpQuickActionsSource', () {
    test(
      'posts to /chat/quick-actions with follow_up and last_recommendations recap',
      () async {
        RequestOptions? captured;
        final src = HttpQuickActionsSource(
          _dio((options) async {
            captured = options;
            return _quickActionsEnvelope(['换一批', '相似导师', '只看985', '偏应用']);
          }),
        );

        final result = await src.fetch(
          followUp: '换一批',
          lastResult: _resultWith([_rec]),
        );

        expect(captured!.path, '/api/v1/chat/quick-actions');
        expect(captured!.method, 'POST');
        expect((captured!.data as Map)['follow_up'], '换一批');
        final recap = (captured!.data as Map)['last_recommendations'] as List;
        expect(recap, hasLength(1));
        expect((recap.single as Map)['professor_id'], 'p_001');
        expect((recap.single as Map)['research_fields'], ['计算机视觉', '医学影像']);
        expect(result, isA<Success<List<String>>>());
        expect((result as Success<List<String>>).data, isNotEmpty);
      },
    );

    test('omits last_recommendations when lastResult is null', () async {
      RequestOptions? captured;
      final src = HttpQuickActionsSource(
        _dio((options) async {
          captured = options;
          return _quickActionsEnvelope(['换一批', '偏应用', '只看985', '适合硕士']);
        }),
      );

      await src.fetch(followUp: '换一批', lastResult: null);

      expect(
        (captured!.data as Map).containsKey('last_recommendations'),
        isFalse,
      );
    });

    test('caps recap to 5 recommendations', () async {
      final recs = [
        for (var i = 0; i < 7; i++)
          Recommendation(
            professorId: 'p_$i',
            name: '导师$i',
            university: '大学$i',
            college: '学院',
            title: '教授',
            researchFields: ['计算机视觉'],
            matchLevel: MatchLevel.medium,
            reason: 'r',
            limitations: [],
          ),
      ];
      RequestOptions? captured;
      final src = HttpQuickActionsSource(
        _dio((options) async {
          captured = options;
          return _quickActionsEnvelope(['换一批', '偏应用', '只看985', '适合硕士']);
        }),
      );

      await src.fetch(followUp: '换一批', lastResult: _resultWith(recs));

      expect(
        (captured!.data as Map)['last_recommendations'] as List,
        hasLength(5),
      );
    });

    test('decodes quick_actions list as Success', () async {
      final src = HttpQuickActionsSource(
        _dio(
          (_) async => _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {
                'quick_actions': ['换一批', '偏应用'],
              },
            }),
          ),
        ),
      );

      final result = await src.fetch(followUp: 'x', lastResult: null);

      expect(result, isA<Success<List<String>>>());
      expect((result as Success<List<String>>).data, ['换一批', '偏应用']);
    });

    test('empty quick_actions decodes as Success with empty list', () async {
      final src = HttpQuickActionsSource(
        _dio(
          (_) async => _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {'quick_actions': <String>[]},
            }),
          ),
        ),
      );

      final result = await src.fetch(followUp: 'x', lastResult: null);

      expect(result, isA<Success<List<String>>>());
      expect((result as Success<List<String>>).data, isEmpty);
    });

    test('non-zero envelope returns Failure', () async {
      final src = HttpQuickActionsSource(
        _dio(
          (_) async => _jsonString(
            jsonEncode({'code': 40001, 'message': '输入内容不合法', 'data': null}),
          ),
        ),
      );

      final result = await src.fetch(followUp: 'x', lastResult: null);

      expect(result, isA<Failure<List<String>>>());
    });

    test(
      'malformed success data (bad field) decodes as Success empty',
      () async {
        final src = HttpQuickActionsSource(
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

        // quick_actions 缺省 → ResponseDto 返回空，但 guardApi 仍 Success([])。
        // 此 case 验证 data 是 Map（含 bad 字段）时 quick_actions 视为空 → Success([])。
        final result = await src.fetch(followUp: 'x', lastResult: null);
        expect(result, isA<Success<List<String>>>());
        expect((result as Success<List<String>>).data, isEmpty);
      },
    );

    test('DioException returns Failure', () async {
      final src = HttpQuickActionsSource(
        _dio((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          );
        }),
      );

      final result = await src.fetch(followUp: 'x', lastResult: null);

      expect(result, isA<Failure<List<String>>>());
      expect((result as Failure<List<String>>).error, isA<TimeoutException>());
    });

    test('never throws — self-degrades per interface contract', () async {
      final src = HttpQuickActionsSource(
        _dio((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }),
      );

      // 接口契约要求降级返回 Failure，不得抛错阻断对话。
      final result = await src.fetch(followUp: 'x', lastResult: null);
      expect(result, isA<Failure<List<String>>>());
    });
  });
}
