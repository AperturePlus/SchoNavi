import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/error/app_exception.dart';
import '../../core/error/error_diagnostics.dart';
import '../../core/result/result.dart';

typedef JsonDecoder<T> = T Function(Object? data);

const _readinessSourceUnavailableCode = 'readiness_source_unavailable';
const _professorDetailReadinessMessage =
    '导师详情暂时加载失败，数据正在读取或更新，请稍后重试';
const _genericReadinessMessage = '服务数据暂时不可用，请稍后重试';
final _professorDetailPathPattern = RegExp(r'^/api/v1/professors/[^/]+$');

Future<Result<T>> guardApi<T>(
  Future<Response<dynamic>> Function() request,
  JsonDecoder<T> decode,
) async {
  Response<dynamic>? response;
  try {
    response = await request();
    return Success(decodeEnvelope(response.data, decode));
  } on AppException catch (error) {
    final details = response == null ? null : _responseDiagnostics(response);
    return Failure(details == null ? error : error.withDiagnostics(details));
  } on DioException catch (error) {
    return Failure(mapDioException(error));
  } catch (error, stackTrace) {
    final details = ErrorDiagnostics(
      exceptionType: error.runtimeType.toString(),
      cause: error.toString(),
      stackTrace: stackTrace.toString(),
      occurredAt: DateTime.now(),
    );
    return Failure(UnknownException(diagnostics: details));
  }
}

T decodeEnvelope<T>(Object? payload, JsonDecoder<T> decode) {
  if (payload is! Map) {
    throw ServerException(
      message: '服务返回格式异常',
      diagnostics: ErrorDiagnostics(
        exceptionType: 'ApiEnvelopeFormatException',
        cause: '响应不是 JSON 对象',
        responsePreview: sanitizedResponsePreview(payload),
        occurredAt: DateTime.now(),
      ),
    );
  }
  final json = Map<String, dynamic>.from(payload);
  final code = json['code'];
  final message = json['message']?.toString();
  if (code != 0) {
    throw ValidationException(
      message == null || message.isEmpty ? '请求失败，请稍后重试' : message,
      diagnostics: ErrorDiagnostics(
        backendCode: code?.toString(),
        backendMessage: message,
        exceptionType: 'ApiBusinessException',
        responsePreview: sanitizedResponsePreview(payload),
        occurredAt: DateTime.now(),
      ),
    );
  }
  if (!json.containsKey('data')) {
    throw ServerException(
      message: '服务返回格式异常',
      diagnostics: ErrorDiagnostics(
        exceptionType: 'ApiEnvelopeFormatException',
        cause: '成功信封缺少 data 字段',
        responsePreview: sanitizedResponsePreview(payload),
        occurredAt: DateTime.now(),
      ),
    );
  }
  try {
    return decode(json['data']);
  } on AppException {
    rethrow;
  } catch (error, stackTrace) {
    throw ServerException(
      message: '服务返回格式异常',
      diagnostics: ErrorDiagnostics(
        exceptionType: error.runtimeType.toString(),
        cause: error.toString(),
        stackTrace: stackTrace.toString(),
        responsePreview: sanitizedResponsePreview(payload),
        occurredAt: DateTime.now(),
      ),
    );
  }
}

AppException mapDioException(DioException error) {
  final details = _dioDiagnostics(error);
  return _mapDioException(error, details, responseData: error.response?.data);
}

Future<AppException> mapDioExceptionWithResponsePreview(
  DioException error,
) async {
  final streamPayload = await _readResponseBody(error.response?.data);
  if (streamPayload == null) return mapDioException(error);
  final responseData = streamPayload.decoded ?? streamPayload.text;
  final details = _dioDiagnostics(error, responseData: responseData);
  return _mapDioException(error, details, responseData: responseData);
}

AppException _mapDioException(
  DioException error,
  ErrorDiagnostics details, {
  required Object? responseData,
}) {
  final underlying = error.error;
  if (underlying is AppException) return underlying.withDiagnostics(details);
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return TimeoutException(diagnostics: details);
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      return NetworkException(diagnostics: details);
    case DioExceptionType.badResponse:
      return _responseException(
        error.response,
        details,
        responseData: responseData,
      );
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      return UnknownException(diagnostics: details);
  }
}

AppException _responseException(
  Response<dynamic>? response,
  ErrorDiagnostics details, {
  Object? responseData,
}) {
  final data = responseData ?? response?.data;
  final message = _backendField(data, 'message');
  final errorCode = _backendField(data, 'error_code');
  final diagnostics = _withBackendContext(details, data);
  final statusCode = response?.statusCode;
  if (statusCode == 503 && errorCode == _readinessSourceUnavailableCode) {
    return ServerException(
      message: _readinessMessageFor(diagnostics.path),
      diagnostics: diagnostics,
    );
  }
  if (statusCode == 422) {
    return ValidationException(
      message == null || message.isEmpty ? '输入内容校验失败' : message,
      diagnostics: diagnostics,
    );
  }
  if (statusCode != null) {
    return AppException.fromStatusCode(
      statusCode,
      message: message == null || message.isEmpty ? null : message,
      diagnostics: diagnostics,
    );
  }
  return UnknownException(diagnostics: diagnostics);
}

ErrorDiagnostics _withBackendContext(ErrorDiagnostics details, Object? data) {
  final context = _backendContext(data);
  if (context.isEmpty) return details;
  return details.copyWith(context: {...details.context, ...context});
}

Map<String, String> _backendContext(Object? data) {
  if (data is! Map) return const {};
  final context = <String, String>{};
  void add(String key, Object? value) {
    final text = value?.toString();
    if (text != null && text.isNotEmpty) context[key] = text;
  }

  add('error_code', data['error_code']);
  final payload = data['data'];
  if (payload is Map) {
    add('data.source', payload['source']);
    add('data.retryable', payload['retryable']);
  }
  return context;
}

String _readinessMessageFor(String? path) {
  return _professorDetailPathPattern.hasMatch(path ?? '')
      ? _professorDetailReadinessMessage
      : _genericReadinessMessage;
}

ErrorDiagnostics _dioDiagnostics(DioException error, {Object? responseData}) {
  final response = error.response;
  final request = error.requestOptions;
  final data = responseData ?? response?.data;
  final responseDetails = response == null
      ? null
      : _responseDiagnostics(response, responseData: data);
  final fallback = ErrorDiagnostics(
    requestId: _requestId(response, request),
    method: request.method,
    path: request.uri.path,
    httpStatus: response?.statusCode,
    backendCode: _backendField(data, 'code'),
    backendMessage: _backendField(data, 'message'),
    exceptionType: error.type.name,
    cause: error.error?.toString() ?? error.message,
    responsePreview: sanitizedResponsePreview(data),
    occurredAt: DateTime.now(),
  );
  return responseDetails?.merge(fallback) ?? fallback;
}

ErrorDiagnostics _responseDiagnostics(
  Response<dynamic> response, {
  Object? responseData,
}) {
  final request = response.requestOptions;
  final data = responseData ?? response.data;
  return ErrorDiagnostics(
    requestId: _requestId(response, request),
    method: request.method,
    path: request.uri.path,
    httpStatus: response.statusCode,
    backendCode: _backendField(data, 'code'),
    backendMessage: _backendField(data, 'message'),
    responsePreview: sanitizedResponsePreview(data),
    occurredAt: DateTime.now(),
  );
}

Future<_ResponseBodyPayload?> _readResponseBody(Object? data) async {
  if (data is! ResponseBody) return null;
  try {
    final bytes = <int>[];
    var truncated = false;
    await for (final chunk in data.stream) {
      final remaining = maxErrorResponsePreviewLength - bytes.length;
      if (remaining <= 0) {
        truncated = true;
        break;
      }
      if (chunk.length > remaining) {
        bytes.addAll(chunk.take(remaining));
        truncated = true;
        break;
      }
      bytes.addAll(chunk);
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    if (truncated) text = '$text…（已截断）';
    return _ResponseBodyPayload(text: text, decoded: _tryDecodeJson(text));
  } catch (error) {
    return _ResponseBodyPayload(
      text: 'ResponseBody stream read failed: $error',
      decoded: null,
    );
  }
}

Object? _tryDecodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

class _ResponseBodyPayload {
  const _ResponseBodyPayload({required this.text, required this.decoded});

  final String text;
  final Object? decoded;
}

String? _requestId(Response<dynamic>? response, RequestOptions request) {
  final echoed = response?.headers.value('x-request-id');
  if (echoed != null && echoed.isNotEmpty) return echoed;
  final header = request.headers.entries
      .where((entry) => entry.key.toLowerCase() == 'x-request-id')
      .map((entry) => entry.value?.toString())
      .firstOrNull;
  return header == null || header.isEmpty ? null : header;
}

String? _backendField(Object? data, String key) {
  if (data is! Map || !data.containsKey(key)) return null;
  return data[key]?.toString();
}

Map<String, dynamic> asJsonObject(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException();
}

List<String> stringList(Object? value) {
  return (value as List<dynamic>? ?? const <dynamic>[])
      .map((item) => item.toString())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
