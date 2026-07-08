import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/data/http/http_preparation_template_provider.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart'
    show CompetitionTimelineType;

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
  test('load sends preparation template query parameters', () async {
    final captures = <RequestOptions>[];
    final provider = HttpPreparationTemplateProvider(
      _dio((options) async {
        captures.add(options);
        return _json(_templateEnvelope());
      }),
    );

    await provider.load(
      timelineType: CompetitionTimelineType.submission,
      includeDefense: true,
      category: '计算机类',
      competitionId: 'comp_icpc',
    );
    await provider.load(
      timelineType: CompetitionTimelineType.eventWindow,
      includeDefense: false,
      category: '创新创业类',
      competitionId: 'comp_innovation',
    );

    expect(captures, hasLength(2));
    expect(captures.first.path, '/api/v1/preparation-templates');
    expect(captures.first.method, 'GET');
    expect(captures.first.queryParameters, {
      'timeline_type': 'submission',
      'include_defense': true,
      'category': '计算机类',
      'competition_id': 'comp_icpc',
    });
    expect(captures.last.queryParameters, {
      'timeline_type': 'eventWindow',
      'include_defense': false,
      'category': '创新创业类',
      'competition_id': 'comp_innovation',
    });
  });
}

Dio _dio(Future<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.httpClientAdapter = _FakeAdapter(handler);
  return dio;
}

ResponseBody _json(Map<String, dynamic> body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _templateEnvelope() => {
  'code': 0,
  'message': 'ok',
  'data': {
    'phases': [
      {
        'key': 'proposal_writing',
        'title': '方案撰写',
        'weight': 1,
        'required_tasks': [
          {
            'template_key': 'proposal_outline',
            'title': '完成方案大纲',
            'estimated_hours': 2,
          },
        ],
        'optional_tasks': [],
      },
    ],
  },
};
