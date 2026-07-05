import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/storage/local_store.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/features/profile/pages/profile_page.dart';

class _Repo implements ProfileRepository {
  _Repo(this._p);
  UserProfile _p;
  @override
  UserProfile load() => _p;
  @override
  Future<UserProfile> refresh() async => load();
  @override
  Future<void> save(UserProfile profile) async => _p = profile;
  @override
  Future<void> clear() async {}
}

class _RefreshingRepo implements ProfileRepository {
  _RefreshingRepo({required this.refreshed, this.throwOnRefresh = false});

  final UserProfile refreshed;
  final bool throwOnRefresh;
  UserProfile _stored = const UserProfile();
  int refreshCount = 0;

  @override
  UserProfile load() => _stored;

  @override
  Future<UserProfile> refresh() async {
    refreshCount++;
    if (throwOnRefresh) throw StateError('profile sync failed');
    _stored = refreshed;
    return _stored;
  }

  @override
  Future<void> save(UserProfile profile) async => _stored = profile;

  @override
  Future<void> clear() async => _stored = const UserProfile();
}

class _AgreedStore implements LocalStore {
  _AgreedStore({required this.agreed});
  final bool agreed;
  @override
  bool? getBool(String key) => key == 'privacy_agreed' ? agreed : null;
  @override
  Future<void> setBool(String key, bool value) async {}
  @override
  String? getString(String key) => null;
  @override
  Future<void> setString(String key, String value) async {}
  @override
  Map<String, dynamic>? getJson(String key) => null;
  @override
  Future<void> setJson(String key, Map<String, dynamic> value) async {}
  @override
  List<dynamic>? getJsonList(String key) => null;
  @override
  Future<void> setJsonList(String key, List<dynamic> value) async {}
  @override
  bool containsKey(String key) => false;
  @override
  Future<void> remove(String key) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  GoRouter routerForProfilePage() {
    return GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        GoRoute(
          path: '/profile/intro',
          builder: (_, _) => const Scaffold(body: Center(child: Text('intro'))),
        ),
        GoRoute(
          path: '/profile/privacy',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('privacy'))),
        ),
      ],
    );
  }

  testWidgets('展示分区卡与完成度', (tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            _Repo(const UserProfile(name: '张三', gender: Gender.male)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('基本信息'), findsOneWidget);
    expect(find.text('竞赛成果'), findsOneWidget);
  });

  testWidgets('档案页右上角设置入口进入设置页', (tester) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
        GoRoute(
          path: '/settings',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('settings'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(
            _Repo(const UserProfile(name: '张三', gender: Gender.male)),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('settings'), findsOneWidget);
  });

  testWidgets('空 profile 只触发一次引导 push', (tester) async {
    final pushed = <String>[];
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_Repo(const UserProfile())),
        localStoreProvider.overrideWithValue(_AgreedStore(agreed: true)),
      ],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(
          path: '/profile',
          builder: (_, _) => const ProfilePage(),
        ),
        GoRoute(
          path: '/profile/intro',
          builder: (_, _) => const Scaffold(body: Center(child: Text('intro'))),
        ),
        GoRoute(
          path: '/profile/privacy',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('privacy'))),
        ),
      ],
    );
    router.routerDelegate.addListener(() {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('intro'), findsOneWidget);
    // 回退到 profile
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('我的档案'), findsOneWidget);
    // 触发 ProfilePage 重建（切换数据源），build 副作用不应再次 push intro
    container.read(appConfigProvider.notifier).setDataSource(DataSource.http);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('intro'), findsNothing);
    pushed; // 保留以备调试
  });

  testWidgets('http profile 首次 load 为空但 refresh 非空时不跳引导', (
    tester,
  ) async {
    final repo = _RefreshingRepo(
      refreshed: const UserProfile(name: '张三', gender: Gender.male),
    );
    final container = ProviderContainer(
      overrides: [
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
        profileRepositoryProvider.overrideWithValue(repo),
        localStoreProvider.overrideWithValue(_AgreedStore(agreed: true)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: routerForProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的档案'), findsOneWidget);
    expect(find.text('intro'), findsNothing);
    expect(repo.refreshCount, 1);
  });

  testWidgets('http profile refresh 成功返回空档案时仍进入引导', (tester) async {
    final repo = _RefreshingRepo(refreshed: const UserProfile());
    final container = ProviderContainer(
      overrides: [
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
        profileRepositoryProvider.overrideWithValue(repo),
        localStoreProvider.overrideWithValue(_AgreedStore(agreed: true)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: routerForProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('intro'), findsOneWidget);
    expect(repo.refreshCount, 1);
  });

  testWidgets('http profile refresh 失败时不误跳引导', (tester) async {
    final repo = _RefreshingRepo(
      refreshed: const UserProfile(),
      throwOnRefresh: true,
    );
    final container = ProviderContainer(
      overrides: [
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(dataSource: DataSource.http),
        ),
        profileRepositoryProvider.overrideWithValue(repo),
        localStoreProvider.overrideWithValue(_AgreedStore(agreed: true)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: routerForProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的档案'), findsOneWidget);
    expect(find.text('intro'), findsNothing);
    expect(repo.refreshCount, 1);
  });
}
