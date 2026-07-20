import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/router/app_router.dart';
import 'package:scho_navi/features/onboarding/pages/onboarding_page.dart';

import '../../helpers/stub_api_dio.dart';

Future<Widget> _app(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(stubDio()),
      apiIdentityDioProvider.overrideWithValue(stubDio()),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('未读引导时从 /home 重定向到 /onboarding', (tester) async {
    await tester.pumpWidget(await _app(<String, Object>{}));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsOneWidget);
  });

  testWidgets('已读引导时停在首页', (tester) async {
    await tester.pumpWidget(
      await _app(<String, Object>{'seenOnboarding': true}),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('正式路由 initialLocation 为 /home', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'seenOnboarding': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    expect(router.routeInformationProvider.value.uri.toString(), '/home');
  });
}
