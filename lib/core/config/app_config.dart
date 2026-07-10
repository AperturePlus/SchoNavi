import 'package:flutter_riverpod/flutter_riverpod.dart';

class FeatureFlags {
  const FeatureFlags({
    this.showMatchScore = false,
    this.showApiErrorDetails = false,
  });

  final bool showMatchScore;
  final bool showApiErrorDetails;

  FeatureFlags copyWith({bool? showMatchScore, bool? showApiErrorDetails}) =>
      FeatureFlags(
        showMatchScore: showMatchScore ?? this.showMatchScore,
        showApiErrorDetails: showApiErrorDetails ?? this.showApiErrorDetails,
      );
}

class ApiConfig {
  const ApiConfig({this.baseUrl = ''});

  final String baseUrl;

  bool get isConfigured => baseUrl.isNotEmpty;
}

class AppConfig {
  const AppConfig({
    this.appVersion = '0.1.0',
    this.featureFlags = const FeatureFlags(),
    this.api = const ApiConfig(),
  });

  final String appVersion;
  final FeatureFlags featureFlags;
  final ApiConfig api;

  AppConfig copyWith({
    String? appVersion,
    FeatureFlags? featureFlags,
    ApiConfig? api,
  }) => AppConfig(
    appVersion: appVersion ?? this.appVersion,
    featureFlags: featureFlags ?? this.featureFlags,
    api: api ?? this.api,
  );

  factory AppConfig.resolve({
    String apiBaseUrl = '',
    String appVersion = '0.1.0',
    bool showApiErrorDetails = false,
  }) => AppConfig(
    appVersion: appVersion,
    featureFlags: FeatureFlags(showApiErrorDetails: showApiErrorDetails),
    api: ApiConfig(baseUrl: _normalizeApiBaseUrl(apiBaseUrl)),
  );

  static String _normalizeApiBaseUrl(String value) {
    var trimmed = value.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    const suffix = '/api/v1';
    if (trimmed.endsWith(suffix)) {
      trimmed = trimmed.substring(0, trimmed.length - suffix.length);
    }
    return trimmed;
  }
}

/// 启动注入的初值（main 用 dart-define 解析后 override；测试可 override）。
final initialAppConfigProvider = Provider<AppConfig>(
  (ref) => const AppConfig(),
);

final appConfigProvider = Provider<AppConfig>(
  (ref) => ref.watch(initialAppConfigProvider),
);
