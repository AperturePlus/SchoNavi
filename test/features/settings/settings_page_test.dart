import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/favorite_item.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/favorite_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/features/settings/pages/settings_page.dart';

Future<Widget> _wrap(AppConfig initial) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(initial),
    ],
    child: const MaterialApp(home: SettingsPage()),
  );
}

Future<Widget> _wrapWithRouter(AppConfig initial) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/feedback',
        builder: (_, state) => Scaffold(
          body: Text(
            'feedback:${state.uri.queryParameters['type']}:'
            '${state.uri.queryParameters['route']}',
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(initial),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

class _FakeFavoriteRepo implements FavoriteRepository {
  @override
  List<FavoriteItem> list() => const [];
  @override
  Stream<List<FavoriteItem>> watch() => Stream.value(const []);
  @override
  bool isFavorite(String professorId) => false;
  @override
  Future<void> add(FavoriteItem item) async {}
  @override
  Future<void> remove(String professorId) async {}
  @override
  Future<bool> toggle(FavoriteItem item) async => true;
}

class _FailingHistoryRepo implements HistoryRepository {
  @override
  List<SearchHistoryItem> list() => const [];
  @override
  Stream<List<SearchHistoryItem>> watch() => Stream.value(const []);
  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async => null;
  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {}
  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {}
  @override
  Future<void> remove(String sessionId) async {}
  @override
  Future<void> clear() async => throw const ValidationException('远端删除失败');
}

class _FakeProfileRepo implements ProfileRepository {
  @override
  UserProfile load() => const UserProfile();
  @override
  Future<UserProfile> refresh() async => load();
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('HTTP 模式展示远端资料文案', (tester) async {
    await tester.pumpWidget(
      await _wrap(
        AppConfig.resolve(apiKey: '', apiBaseUrl: 'https://api.example.com'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('删除远端资料'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('会同步到后端'), findsOneWidget);
    expect(find.textContaining('资料仅保存在本机'), findsNothing);
  });

  testWidgets('设置页关于区域展示中文产品名', (tester) async {
    await tester.pumpWidget(await _wrap(const AppConfig()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('蓝星竞航'),
      300,
      scrollable: find.byType(Scrollable),
    );

    expect(find.text('蓝星竞航'), findsOneWidget);
    expect(find.textContaining('SchoNavi · 用自然语言找到适合你的导师'), findsOneWidget);
  });

  testWidgets('设置页可选择并持久化主题模式', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('根据设备深色模式自动切换'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-theme-mode-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(prefs.getString(appThemeModePreferenceKey), 'dark');
    expect(find.text('深色'), findsOneWidget);
    expect(find.text('始终使用深色外观'), findsOneWidget);
  });

  testWidgets('设置页意见反馈入口进入反馈页', (tester) async {
    await tester.pumpWidget(await _wrapWithRouter(const AppConfig()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-feedback-entry')),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.byKey(const Key('settings-feedback-entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-feedback-entry')));
    await tester.pumpAndSettle();

    expect(find.text('feedback:other:/settings'), findsOneWidget);
  });

  testWidgets('HTTP 远端清除失败时展示错误', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          initialAppConfigProvider.overrideWithValue(
            AppConfig.resolve(
              apiKey: '',
              apiBaseUrl: 'https://api.example.com',
            ),
          ),
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
          historyRepositoryProvider.overrideWithValue(_FailingHistoryRepo()),
          profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除远端资料'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('远端删除失败'), findsOneWidget);
  });
}
