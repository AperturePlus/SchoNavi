import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/router/app_router.dart';
import 'package:scho_navi/features/chat/pages/chat_page.dart';

import '../../helpers/stub_api_dio.dart';

void main() {
  testWidgets('app router 把 /chat 解析为 ChatPage', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'seenOnboarding': true,
    });
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    router.go('/chat?sid=s_x');
    await tester.pumpAndSettle();

    // ChatPage 不再有 AppBar；改为断言悬浮按钮存在，验证路由仍落地 ChatPage。
    // /chat?sid= 是旧会话追问入口（推荐页/详情页「继续追问」push 进来），
    // 左上为「返回」而非「新对话」。
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
  });

  testWidgets('/chat?fork&msid=&pid= 解析并落地 ChatPage', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'seenOnboarding': true,
    });
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 3));

    router.go('/chat?fork=true&msid=s1&pid=p_001');
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsOneWidget);
  });
}
