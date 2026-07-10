import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';

ProviderContainer _c(AppConfig initial) => ProviderContainer(
  overrides: [initialAppConfigProvider.overrideWithValue(initial)],
);

void main() {
  test('app config is a read-only HTTP configuration provider', () {
    final c = _c(AppConfig.resolve(apiBaseUrl: 'https://api.example.com'));
    addTearDown(c.dispose);
    expect(c.read(appConfigProvider).api.baseUrl, 'https://api.example.com');
  });
}
