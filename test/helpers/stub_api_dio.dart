import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:scho_navi/core/di/providers.dart';

/// 全 App pump 时所有业务 provider 均走 HTTP；无后端会让 FutureProvider 永不
/// settle。本适配器对匿名身份端点返回合法 token 信封，其余路径返回 404 信封，
/// 让 HTTP provider 快速落到 Failure/空状态，widget 测试得以 pumpAndSettle。
class StubApiAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final body = options.path.endsWith('/identity/anonymous')
        ? {
            'code': 0,
            'message': 'ok',
            'data': {'access_token': 'stub-token'},
          }
        : {'code': 40401, 'message': 'not found', 'data': null};
    return Future.value(
      ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
  }
}

/// 构造一个指向 stub 适配器的 Dio，用于覆盖 [dioProvider] /
/// [apiIdentityDioProvider]，避免全 App widget 测试发起真实网络调用。
Dio stubDio() =>
    Dio(BaseOptions(baseUrl: 'https://stub.local'))
      ..httpClientAdapter = StubApiAdapter();
