import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';

void main() {
  test('missing API_BASE_URL keeps the app unconfigured', () {
    final cfg = AppConfig.resolve();
    expect(cfg.api.isConfigured, isFalse);
    expect(cfg.api.baseUrl, isEmpty);
  });

  test('API_BASE_URL is normalized to a backend origin', () {
    final cfg = AppConfig.resolve(
      apiBaseUrl: 'https://api.example.com/api/v1/',
    );
    expect(cfg.api.isConfigured, isTrue);
    expect(cfg.api.baseUrl, 'https://api.example.com');
  });

  test('API error details are opt-in through resolved config', () {
    expect(AppConfig.resolve().featureFlags.showApiErrorDetails, isFalse);
    expect(
      AppConfig.resolve(
        showApiErrorDetails: true,
      ).featureFlags.showApiErrorDetails,
      isTrue,
    );
  });
}
