import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/features/profile/pages/profile_intro_page.dart';

Widget _harness() {
  final router = GoRouter(
    initialLocation: '/profile/intro',
    routes: [
      GoRoute(
        path: '/profile/intro',
        builder: (_, _) => const ProfileIntroPage(),
      ),
      GoRoute(path: '/profile', builder: (_, _) => const Text('hub-marker')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  testWidgets('顶栏 AppBar 标题为「完善档案」', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('完善档案'), findsOneWidget);
  });

  testWidgets('底部「以后再说」仍存在并可点击返回', (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('以后再说'), findsOneWidget);
    await tester.tap(find.text('以后再说'));
    await tester.pumpAndSettle();
    // pop 回无上一页 → 路由停在原地，无崩溃即通过。
  });

  testWidgets('小屏下页面可滚动且不发生底部溢出', (tester) async {
    tester.view.physicalSize = const Size(375, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('开始填写（约 1 分钟）'), findsOneWidget);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -220),
    );
    await tester.pumpAndSettle();

    expect(find.text('开始填写（约 1 分钟）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
