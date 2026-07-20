import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';

void main() {
  test('each AppException carries a user-facing Chinese message', () {
    expect(const NetworkException().message, contains('网络'));
    expect(const TimeoutException().message, contains('超时'));
    expect(const BadRequestException().message, contains('不合法'));
    expect(const UnauthorizedException().message, contains('登录'));
    expect(
      const MissingApiConfigurationException().message,
      contains('API_BASE_URL'),
    );
    expect(const ForbiddenException().message, contains('权限'));
    expect(const NotFoundException().message, contains('不存在'));
    expect(const RateLimitException().message, contains('频繁'));
    expect(const ServerException().message, contains('服务'));
    expect(const UnknownException().message, isNotEmpty);
  });

  test('AppException.fromStatusCode maps HTTP codes', () {
    expect(AppException.fromStatusCode(400), isA<BadRequestException>());
    expect(AppException.fromStatusCode(401), isA<UnauthorizedException>());
    expect(AppException.fromStatusCode(403), isA<ForbiddenException>());
    expect(AppException.fromStatusCode(404), isA<NotFoundException>());
    expect(AppException.fromStatusCode(409), isA<ConflictException>());
    expect(AppException.fromStatusCode(429), isA<RateLimitException>());
    expect(AppException.fromStatusCode(500), isA<ServerException>());
    expect(AppException.fromStatusCode(418), isA<UnknownException>());
  });
}
