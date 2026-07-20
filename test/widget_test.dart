import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/app.dart';
import 'package:scho_navi/core/di/providers.dart';

import 'helpers/stub_api_dio.dart';

Future<ProviderScope> _wrap() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'seenOnboarding': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      dioProvider.overrideWithValue(stubDio()),
      apiIdentityDioProvider.overrideWithValue(stubDio()),
    ],
    child: const SchoNaviApp(),
  );
}

void main() {
  testWidgets('App boots into home page', (tester) async {
    await tester.pumpWidget(await _wrap());
    await tester.pumpAndSettle();
    expect(find.text('SchoNavi'), findsOneWidget);
    expect(find.byTooltip('菜单'), findsOneWidget);
  });

  testWidgets('App uses persisted theme mode', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'seenOnboarding': true,
      appThemeModePreferenceKey: 'dark',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dioProvider.overrideWithValue(stubDio()),
          apiIdentityDioProvider.overrideWithValue(stubDio()),
        ],
        child: const SchoNaviApp(),
      ),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}
