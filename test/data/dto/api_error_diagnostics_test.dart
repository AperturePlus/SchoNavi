import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/error/error_diagnostics.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/dto/api_envelope.dart';

void main() {
  test(
    'business failure preserves request metadata and backend code',
    () async {
      final result = await guardApi<Object?>(
        () async => Response<dynamic>(
          requestOptions: RequestOptions(
            path: '/api/v1/profile',
            method: 'POST',
            headers: {'X-Request-ID': 'client-request'},
          ),
          statusCode: 200,
          headers: Headers.fromMap({
            'x-request-id': ['server-request'],
          }),
          data: {'code': 42201, 'message': '字段校验失败', 'data': null},
        ),
        (data) => data,
      );

      final error = (result as Failure<Object?>).error;
      expect(error, isA<ValidationException>());
      expect(error.message, '字段校验失败');
      expect(error.diagnostics?.requestId, 'server-request');
      expect(error.diagnostics?.method, 'POST');
      expect(error.diagnostics?.path, '/api/v1/profile');
      expect(error.diagnostics?.backendCode, '42201');
      expect(error.diagnostics?.httpStatus, 200);
    },
  );

  test(
    'decode failure retains cause and a redacted response preview',
    () async {
      final result = await guardApi<String>(
        () async => Response<dynamic>(
          requestOptions: RequestOptions(
            path: '/api/v1/profile',
            method: 'GET',
            headers: {'X-Request-ID': 'request-1'},
          ),
          statusCode: 200,
          data: {
            'code': 0,
            'message': 'ok',
            'data': {'access_token': 'secret-token', 'value': 'unexpected'},
          },
        ),
        (_) => throw const FormatException('missing profile.name'),
      );

      final error = (result as Failure<String>).error;
      expect(error, isA<ServerException>());
      expect(error.diagnostics?.cause, contains('missing profile.name'));
      expect(error.diagnostics?.responsePreview, contains('[REDACTED]'));
      expect(
        error.diagnostics?.responsePreview,
        isNot(contains('secret-token')),
      );
    },
  );

  test(
    'bad HTTP responses preserve status, backend message and request ID',
    () {
      final request = RequestOptions(
        path: '/api/v1/history',
        method: 'DELETE',
        headers: {'X-Request-ID': 'request-409'},
      );
      final exception = DioException.badResponse(
        statusCode: 409,
        requestOptions: request,
        response: Response<dynamic>(
          requestOptions: request,
          statusCode: 409,
          data: {'code': 40901, 'message': '版本冲突', 'data': null},
        ),
      );

      final error = mapDioException(exception);
      expect(error, isA<ConflictException>());
      expect(error.message, '版本冲突');
      expect(error.diagnostics?.httpStatus, 409);
      expect(error.diagnostics?.backendCode, '40901');
      expect(error.diagnostics?.requestId, 'request-409');
    },
  );

  test(
    '503 readiness professor detail hides technical message and preserves context',
    () {
      const technicalMessage = 'readiness source elasticsearch unavailable';
      final request = RequestOptions(
        path: '/api/v1/professors/p1',
        method: 'GET',
        headers: {'X-Request-ID': 'request-503'},
      );
      final exception = DioException.badResponse(
        statusCode: 503,
        requestOptions: request,
        response: Response<dynamic>(
          requestOptions: request,
          statusCode: 503,
          data: {
            'code': 50301,
            'message': technicalMessage,
            'error_code': 'readiness_source_unavailable',
            'data': {'source': 'professor_detail_index', 'retryable': true},
          },
        ),
      );

      final error = mapDioException(exception);

      expect(error, isA<ServerException>());
      expect(error.message, '导师详情暂时加载失败，数据正在读取或更新，请稍后重试');
      expect(error.message, isNot(contains(technicalMessage)));
      expect(error.diagnostics?.backendMessage, technicalMessage);
      expect(
        error.diagnostics?.context,
        containsPair('error_code', 'readiness_source_unavailable'),
      );
      expect(
        error.diagnostics?.context,
        containsPair('data.source', 'professor_detail_index'),
      );
      expect(
        error.diagnostics?.context,
        containsPair('data.retryable', 'true'),
      );
    },
  );

  test('503 readiness on other endpoints uses generic friendly message', () {
    final request = RequestOptions(path: '/api/v1/home/config', method: 'GET');
    final exception = DioException.badResponse(
      statusCode: 503,
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: 503,
        data: {
          'message': 'readiness source unavailable: redis',
          'error_code': 'readiness_source_unavailable',
          'data': {'source': 'home_config', 'retryable': false},
        },
      ),
    );

    final error = mapDioException(exception);

    expect(error, isA<ServerException>());
    expect(error.message, '服务数据暂时不可用，请稍后重试');
    expect(
      error.diagnostics?.context,
      containsPair('data.retryable', 'false'),
    );
  });

  test('stream bad responses decode response body diagnostics', () async {
    final request = RequestOptions(
      path: '/api/v1/chat/sessions/session-1/turns',
      method: 'POST',
      headers: {'X-Request-ID': 'client-stream-request'},
    );
    final exception = DioException.badResponse(
      statusCode: 500,
      requestOptions: request,
      response: Response<dynamic>(
        requestOptions: request,
        statusCode: 500,
        headers: Headers.fromMap({
          'x-request-id': ['server-stream-request'],
        }),
        data: ResponseBody.fromString(
          '{"code":50001,"message":"推荐服务异常","data":null}',
          500,
        ),
      ),
    );

    final error = await mapDioExceptionWithResponsePreview(exception);

    expect(error, isA<ServerException>());
    expect(error.message, '推荐服务异常');
    expect(error.diagnostics?.requestId, 'server-stream-request');
    expect(error.diagnostics?.method, 'POST');
    expect(error.diagnostics?.path, '/api/v1/chat/sessions/session-1/turns');
    expect(error.diagnostics?.httpStatus, 500);
    expect(error.diagnostics?.backendCode, '50001');
    expect(error.diagnostics?.backendMessage, '推荐服务异常');
    expect(error.diagnostics?.responsePreview, contains('推荐服务异常'));
  });

  test('auth interceptor AppException is not collapsed to unknown', () {
    final request = RequestOptions(path: '/api/v1/profile', method: 'GET');
    const original = UnauthorizedException(message: '匿名身份创建失败');
    final mapped = mapDioException(
      DioException(
        requestOptions: request,
        type: DioExceptionType.unknown,
        error: original,
      ),
    );

    expect(mapped, isA<UnauthorizedException>());
    expect(mapped.message, '匿名身份创建失败');
    expect(mapped.diagnostics?.path, '/api/v1/profile');
  });

  test('response previews are truncated and redact private values', () {
    final preview = sanitizedResponsePreview({
      'password': 'do-not-show',
      'contact': '13800000000',
      'payload': List.filled(5000, 'x').join(),
    });

    expect(preview, isNot(contains('do-not-show')));
    expect(preview, isNot(contains('13800000000')));
    expect(preview, contains('[REDACTED]'));
    expect(preview!.length, lessThanOrEqualTo(4110));
    expect(preview, endsWith('…（已截断）'));
  });

  test('response previews fall back for unsupported objects', () {
    final objectPreview = sanitizedResponsePreview(_UnsupportedPreviewObject());
    final preview = sanitizedResponsePreview({
      'api_key': 'do-not-show',
      'payload': _UnsupportedPreviewObject(),
    });

    expect(objectPreview, contains('_UnsupportedPreviewObject'));
    expect(preview, contains('unsupported-preview-object'));
    expect(preview, contains('[REDACTED]'));
    expect(preview, isNot(contains('do-not-show')));
  });
}

class _UnsupportedPreviewObject {
  @override
  String toString() => 'unsupported-preview-object';
}
