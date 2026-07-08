import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/shared/widgets/app_menu_drawer.dart';

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
  _RefreshingRepo(this.refreshed);

  final UserProfile refreshed;
  UserProfile _stored = const UserProfile();
  int refreshCount = 0;

  @override
  UserProfile load() => _stored;

  @override
  Future<UserProfile> refresh() async {
    refreshCount++;
    _stored = refreshed;
    return _stored;
  }

  @override
  Future<void> save(UserProfile profile) async => _stored = profile;

  @override
  Future<void> clear() async => _stored = const UserProfile();
}

class _FakeConversationRepo implements ConversationRepository {
  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async =>
      throw UnimplementedError();

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => throw UnimplementedError();

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async =>
      const Success(null);

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      const Success([]);

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => const Success([]);

  @override
  Future<Result<void>> deleteSession(String sessionId) async =>
      const Success(null);

  @override
  Future<Result<void>> clearSessions() async => const Success(null);
}

Future<Widget> _harness(
  UserProfile profile, {
  bool agreed = false,
  DataSource dataSource = DataSource.llm,
  ProfileRepository? profileRepository,
}) async {
  final initial = <String, Object>{
    if (agreed) 'privacy_agreed': true,
  };
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      initialAppConfigProvider.overrideWithValue(
        AppConfig(dataSource: dataSource),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      profileRepositoryProvider.overrideWithValue(
        profileRepository ?? _Repo(profile),
      ),
      conversationRepositoryProvider.overrideWithValue(_FakeConversationRepo()),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => Scaffold(
          endDrawer: const AppMenuDrawer(),
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Scaffold.of(context).openEndDrawer(),
                child: const Text('Open drawer'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Text('profile-page')),
      ),
      GoRoute(
        path: '/profile/intro',
        builder: (_, _) => const Scaffold(body: Text('intro-page')),
      ),
      GoRoute(
        path: '/profile/privacy',
        builder: (_, _) => const Scaffold(body: Text('privacy-page')),
      ),
    ],
  );

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('空 profile + 已同意隐私：点档案头进入 /profile/intro', (tester) async {
    await tester.pumpWidget(await _harness(const UserProfile(), agreed: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('档案'));
    await tester.pumpAndSettle();

    expect(find.text('intro-page'), findsOneWidget);
    expect(find.text('privacy-page'), findsNothing);
  });

  testWidgets('空 profile + 未同意隐私：点档案头进入 /profile/privacy', (tester) async {
    await tester.pumpWidget(await _harness(const UserProfile(), agreed: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('档案'));
    await tester.pumpAndSettle();

    expect(find.text('privacy-page'), findsOneWidget);
    expect(find.text('intro-page'), findsNothing);
  });

  testWidgets('非空 profile：点档案头进入 /profile', (tester) async {
    await tester.pumpWidget(
      await _harness(const UserProfile(name: '张三', gender: Gender.male)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('档案'));
    await tester.pumpAndSettle();

    expect(find.text('profile-page'), findsOneWidget);
  });

  testWidgets('http profile 首次 load 为空但 refresh 非空时点档案头进入 /profile', (
    tester,
  ) async {
    final repo = _RefreshingRepo(
      const UserProfile(name: '张三', gender: Gender.male),
    );
    await tester.pumpWidget(
      await _harness(
        const UserProfile(),
        agreed: true,
        dataSource: DataSource.http,
        profileRepository: repo,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open drawer'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('档案'));
    await tester.pumpAndSettle();

    expect(find.text('profile-page'), findsOneWidget);
    expect(find.text('intro-page'), findsNothing);
    expect(repo.refreshCount, 1);
  });
}
