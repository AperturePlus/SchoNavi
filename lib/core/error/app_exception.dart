import 'error_diagnostics.dart';

/// 全应用统一异常基类，承载用户可读中文文案和可选诊断上下文。
sealed class AppException implements Exception {
  const AppException(this.message, {this.diagnostics});

  final String message;
  final ErrorDiagnostics? diagnostics;

  AppException withDiagnostics(ErrorDiagnostics details);

  static AppException fromStatusCode(
    int code, {
    String? message,
    ErrorDiagnostics? diagnostics,
  }) {
    switch (code) {
      case 400:
        return BadRequestException(message: message, diagnostics: diagnostics);
      case 401:
        return UnauthorizedException(
          message: message,
          diagnostics: diagnostics,
        );
      case 403:
        return ForbiddenException(message: message, diagnostics: diagnostics);
      case 404:
        return NotFoundException(message: message, diagnostics: diagnostics);
      case 409:
        return ConflictException(message: message, diagnostics: diagnostics);
      case 429:
        return RateLimitException(message: message, diagnostics: diagnostics);
      case >= 500 && <= 599:
        return ServerException(message: message, diagnostics: diagnostics);
      default:
        return UnknownException(message: message, diagnostics: diagnostics);
    }
  }

  @override
  String toString() => '$runtimeType($message)';
}

class NetworkException extends AppException {
  const NetworkException({super.diagnostics}) : super('网络连接失败，请检查网络后重试');

  @override
  NetworkException withDiagnostics(ErrorDiagnostics details) =>
      NetworkException(diagnostics: diagnostics?.merge(details) ?? details);
}

class TimeoutException extends AppException {
  const TimeoutException({super.diagnostics}) : super('请求超时，请稍后重试');

  @override
  TimeoutException withDiagnostics(ErrorDiagnostics details) =>
      TimeoutException(diagnostics: diagnostics?.merge(details) ?? details);
}

class BadRequestException extends AppException {
  const BadRequestException({String? message, super.diagnostics})
    : super(message ?? '输入内容不合法');

  @override
  BadRequestException withDiagnostics(ErrorDiagnostics details) =>
      BadRequestException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.diagnostics});

  @override
  ValidationException withDiagnostics(ErrorDiagnostics details) =>
      ValidationException(
        message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class UnauthorizedException extends AppException {
  const UnauthorizedException({String? message, super.diagnostics})
    : super(message ?? '请先登录');

  @override
  UnauthorizedException withDiagnostics(ErrorDiagnostics details) =>
      UnauthorizedException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class MissingApiConfigurationException extends AppException {
  const MissingApiConfigurationException({super.diagnostics})
    : super('未配置 API_BASE_URL，无法连接真实后端');

  @override
  MissingApiConfigurationException withDiagnostics(ErrorDiagnostics details) =>
      MissingApiConfigurationException(
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class ForbiddenException extends AppException {
  const ForbiddenException({String? message, super.diagnostics})
    : super(message ?? '暂无权限');

  @override
  ForbiddenException withDiagnostics(ErrorDiagnostics details) =>
      ForbiddenException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class NotFoundException extends AppException {
  const NotFoundException({String? message, super.diagnostics})
    : super(message ?? '信息不存在');

  @override
  NotFoundException withDiagnostics(ErrorDiagnostics details) =>
      NotFoundException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class RateLimitException extends AppException {
  const RateLimitException({String? message, super.diagnostics})
    : super(message ?? '请求过于频繁，请稍后再试');

  @override
  RateLimitException withDiagnostics(ErrorDiagnostics details) =>
      RateLimitException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class ServerException extends AppException {
  const ServerException({String? message, super.diagnostics})
    : super(message ?? '服务异常，请稍后重试');

  @override
  ServerException withDiagnostics(ErrorDiagnostics details) => ServerException(
    message: message,
    diagnostics: diagnostics?.merge(details) ?? details,
  );
}

class UnknownException extends AppException {
  const UnknownException({String? message, super.diagnostics})
    : super(message ?? '出错了，请稍后重试');

  @override
  UnknownException withDiagnostics(ErrorDiagnostics details) =>
      UnknownException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

class ConflictException extends AppException {
  const ConflictException({String? message, super.diagnostics})
    : super(message ?? '数据已变化，请刷新后重试');

  @override
  ConflictException withDiagnostics(ErrorDiagnostics details) =>
      ConflictException(
        message: message,
        diagnostics: diagnostics?.merge(details) ?? details,
      );
}

AppException normalizeAppException(Object error, [StackTrace? stackTrace]) {
  if (error is AppException) {
    if (stackTrace == null || error.diagnostics?.stackTrace != null) {
      return error;
    }
    return error.withDiagnostics(
      ErrorDiagnostics(stackTrace: stackTrace.toString()),
    );
  }
  return UnknownException(
    diagnostics: ErrorDiagnostics(
      exceptionType: error.runtimeType.toString(),
      cause: error.toString(),
      stackTrace: stackTrace?.toString(),
      occurredAt: DateTime.now(),
    ),
  );
}
