import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/theme/app_theme.dart';
import 'package:scho_navi/shared/widgets/floating_top_button.dart';

Widget _wrap(Widget child, {ThemeMode themeMode = ThemeMode.light}) =>
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('渲染给定 icon 并暴露 tooltip', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FloatingTopButton(
          icon: Icons.menu_outlined,
          tooltip: '菜单',
          onPressed: null,
        ),
      ),
    );
    expect(find.byIcon(Icons.menu_outlined), findsOneWidget);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('点击触发 onPressed 回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        FloatingTopButton(
          icon: Icons.edit_square,
          tooltip: '新对话',
          onPressed: () => tapped++,
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('onPressed 为 null 时 disabled：icon 用主题弱前景且不触发回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      _wrap(
        FloatingTopButton(
          icon: Icons.refresh,
          tooltip: '重新生成',
          onPressed: null,
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.refresh));
    expect(icon.color, AppTheme.light().colorScheme.onSurfaceVariant);
    // InkWell.onTap 为 null，断言无回调可触发。
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.onTap, isNull);
    expect(tapped, 0);
  });

  testWidgets('深色模式下 enabled icon 使用 onSurface，避免汉堡菜单不可见', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FloatingTopButton(
          icon: Icons.menu_outlined,
          tooltip: '菜单',
          onPressed: () {},
        ),
        themeMode: ThemeMode.dark,
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.menu_outlined));
    expect(icon.color, AppTheme.dark().colorScheme.onSurface);
  });
}
