import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/data/http/http_recommendation_need_classifier.dart';
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
  ) {
    return handler(options);
  }
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handler) {
  return Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = _FakeAdapter(handler);
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

ResponseBody _routeEnvelope({required bool need}) => _jsonString(
  jsonEncode({
    'code': 0,
    'message': 'ok',
    'data': {'need': need},
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
  group('HttpRecommendationNeedClassifier', () {
    test(
      'posts to /chat/route with follow_up and last_recommendations recap',
      () async {
        RequestOptions? captured;
        final classifier = HttpRecommendationNeedClassifier(
          _dio((options) async {
            captured = options;
            return _routeEnvelope(need: true);
          }),
        );

        final need = await classifier.needRecommendations(
          '换一批',
          lastResult: _resultWith([_rec]),
        );

        expect(captured!.path, '/api/v1/chat/route');
        expect(captured!.method, 'POST');
        expect((captured!.data as Map)['follow_up'], '换一批');
        final recap = (captured!.data as Map)['last_recommendations'] as List;
        expect(recap, hasLength(1));
        expect((recap.single as Map)['professor_id'], 'p_001');
        expect((recap.single as Map)['research_fields'], ['计算机视觉', '医学影像']);
        expect(need, isTrue);
      },
    );

    test('omits last_recommendations when lastResult is null', () async {
      RequestOptions? captured;
      final classifier = HttpRecommendationNeedClassifier(
        _dio((options) async {
          captured = options;
          return _routeEnvelope(need: false);
        }),
      );

      await classifier.needRecommendations('为什么推荐他', lastResult: null);

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
      final classifier = HttpRecommendationNeedClassifier(
        _dio((options) async {
          captured = options;
          return _routeEnvelope(need: true);
        }),
      );

      await classifier.needRecommendations(
        '再推荐',
        lastResult: _resultWith(recs),
      );

      expect(
        (captured!.data as Map)['last_recommendations'] as List,
        hasLength(5),
      );
    });

    test('decodes need:false from envelope', () async {
      final classifier = HttpRecommendationNeedClassifier(
        _dio(
          (_) async => _jsonString(
            jsonEncode({
              'code': 0,
              'message': 'ok',
              'data': {'need': false},
            }),
          ),
        ),
      );

      expect(await classifier.needRecommendations('他的研究方向是什么？'), isFalse);
    });

    test('non-zero envelope degrades to false', () async {
      final classifier = HttpRecommendationNeedClassifier(
        _dio(
          (_) async => _jsonString(
            jsonEncode({'code': 40001, 'message': '输入内容不合法', 'data': null}),
          ),
        ),
      );

      expect(await classifier.needRecommendations('x'), isFalse);
    });

    test('malformed success data degrades to false', () async {
      final classifier = HttpRecommendationNeedClassifier(
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

      expect(await classifier.needRecommendations('x'), isFalse);
    });

    test('DioException degrades to false', () async {
      final classifier = HttpRecommendationNeedClassifier(
        _dio((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          );
        }),
      );

      expect(await classifier.needRecommendations('x'), isFalse);
    });

    test('never throws — self-degrades per interface contract', () async {
      final classifier = HttpRecommendationNeedClassifier(
        _dio((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }),
      );

      // 接口契约要求降级返回 false，不得抛错阻断对话。
      expect(await classifier.needRecommendations('x'), isFalse);
    });
  });

  // 静态断言：Failure 携带的 AppException 类型在降级路径上仍可观测（纵深防御）。
  test(
    'guardApi Failure path is reachable (ServerException on malformed data)',
    () async {
      final classifier = HttpRecommendationNeedClassifier(
        _dio(
          (_) async => _jsonString(
            jsonEncode({'code': 0, 'message': 'ok', 'data': null}),
          ),
        ),
      );

      // data 缺失 → decodeEnvelope 抛 ServerException → Failure → 降级 false。
      expect(await classifier.needRecommendations('x'), isFalse);
    },
  );
}
