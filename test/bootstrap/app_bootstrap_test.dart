import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/bootstrap/app_bootstrap.dart';
import 'package:scho_navi/features/onboarding/pages/onboarding_page.dart';
import 'package:scho_navi/features/splash/pages/splash_page.dart';

import '../helpers/stub_api_dio.dart';

Future<SharedPreferences> _preferences({bool seenOnboarding = true}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'seenOnboarding': seenOnboarding,
  });
  return SharedPreferences.getInstance();
}

Widget _app(Future<SharedPreferences> Function() loader) {
  // 注入 stub Dio，让 SchoNaviApp 的 HTTP provider 不发起真实网络调用，
  // 避免 pumpAndSettle 永不结束（HTTP 迁移后所有业务 provider 均走后端）。
  return AppBootstrap(
    preferencesLoader: loader,
    dioOverride: stubDio(),
    identityDioOverride: stubDio(),
  );
}

Future<void> _finishSplash(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('初始化先完成时仍播放完整动画，再进入首页', (tester) async {
    final preferences = await _preferences();
    await tester.pumpWidget(_app(() async => preferences));
    await tester.pump();

    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byTooltip('菜单'), findsNothing);

    await _finishSplash(tester);

    expect(find.byType(SplashPage), findsNothing);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('动画先完成时保持最终帧，初始化完成后进入首页', (tester) async {
    final completer = Completer<SharedPreferences>();
    await tester.pumpWidget(_app(() => completer.future));

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(SplashPage), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );

    completer.complete(await _preferences());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.byType(SplashPage), findsNothing);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('点击跳过只跳过动画，不绕过本地初始化', (tester) async {
    final completer = Completer<SharedPreferences>();
    await tester.pumpWidget(_app(() => completer.future));
    await tester.pump();

    await tester.tap(find.byType(SplashPage));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byTooltip('菜单'), findsNothing);

    completer.complete(await _preferences());
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.byType(SplashPage), findsNothing);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('偏好读取失败时显示错误，并可重试进入首页', (tester) async {
    final preferences = await _preferences();
    var attempts = 0;
    Future<SharedPreferences> loader() {
      attempts++;
      if (attempts == 1) {
        return Future<SharedPreferences>.error(StateError('read failed'));
      }
      return Future<SharedPreferences>.value(preferences);
    }

    await tester.pumpWidget(_app(loader));
    await tester.pump();
    await tester.pump();

    expect(find.text('启动失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.byType(SplashPage), findsOneWidget);

    await _finishSplash(tester);
    expect(attempts, 2);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('首次启动在开屏完成后进入 onboarding', (tester) async {
    final preferences = await _preferences(seenOnboarding: false);
    await tester.pumpWidget(_app(() async => preferences));
    await tester.pump();

    await _finishSplash(tester);

    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.byType(SplashPage), findsNothing);
  });
}
