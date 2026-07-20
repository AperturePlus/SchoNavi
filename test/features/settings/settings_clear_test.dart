import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/auth/anonymous_credential_store.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/platform/preparation_reminder_platform.dart';
import 'package:scho_navi/core/storage/shared_preferences_local_store.dart';
import 'package:scho_navi/data/http/api_auth.dart';
import 'package:scho_navi/domain/entities/assistant_turn.dart';
import 'package:scho_navi/domain/entities/favorite_item.dart';
import 'package:scho_navi/domain/entities/level_diagnosis.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/preparation_reminder.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/favorite_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';
import 'package:scho_navi/features/preparation/providers/preparation_reminder_providers.dart';
import 'package:scho_navi/features/settings/pages/settings_page.dart';

import '../../helpers/stub_api_dio.dart';

PreparationPlan _plan() => PreparationPlan(
  id: 'p1',
  competition: const CompetitionSnapshot(
    id: 'c1',
    name: 'ACM',
    category: '计算机类',
    rulesSummary: CompetitionRulesSummary(
      signupTime: '',
      contestTime: '',
      teamSize: '',
      format: '',
      organizer: '',
    ),
  ),
  targetDate: DateTime(2026, 9, 1),
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.beginner,
  status: PreparationPlanStatus.active,
  phases: const [],
  createdAt: DateTime(2026, 6, 28),
  updatedAt: DateTime(2026, 6, 28),
);

class _NoopFavoriteRepo implements FavoriteRepository {
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
  Future<bool> toggle(FavoriteItem item) async => false;
}

class _NoopHistoryRepo implements HistoryRepository {
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
  Future<void> clear() async {}
}

class _NoopProfileRepo implements ProfileRepository {
  @override
  UserProfile load() => const UserProfile();
  @override
  Future<UserProfile> refresh() async => load();
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> clear() async {}
}

class _FakeCredentialStore implements AnonymousCredentialStore {
  @override
  Future<String?> readToken() async => null;
  @override
  Future<void> writeToken(String token) async {}
  @override
  Future<void> clear() async {}
}

class _FakeReminderPlatform implements PreparationReminderPlatform {
  @override
  bool get isSupported => true;
  @override
  Future<ReminderNotificationStatus> getNotificationStatus() async =>
      ReminderNotificationStatus.granted;
  @override
  Future<void> openNotificationSettings() async {}
  @override
  Future<bool> pinWidget() async => true;
  @override
  Future<CalendarAddResult> addDeadlineEvent(
    CalendarDeadlineEvent event,
  ) async => CalendarAddResult.success;
  @override
  Future<ReminderNotificationStatus> requestNotificationPermission() async =>
      ReminderNotificationStatus.granted;
  @override
  void setRouteHandler(ReminderRouteHandler? handler) {}
  @override
  Future<void> syncSnapshot(PreparationReminderSnapshot snapshot) async {}
  @override
  Future<String?> takeInitialRoute() async => null;
  @override
  Future<void> updateSchedule(ReminderPreferences preferences) async {}
}

Future<ProviderContainer> _bootstrap() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final store = SharedPreferencesLocalStore(prefs);
  final authenticator = ApiAuthenticator(stubDio(), _FakeCredentialStore());
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      localStoreProvider.overrideWithValue(store),
      favoriteRepositoryProvider.overrideWithValue(_NoopFavoriteRepo()),
      historyRepositoryProvider.overrideWithValue(_NoopHistoryRepo()),
      profileRepositoryProvider.overrideWithValue(_NoopProfileRepo()),
      apiAuthenticatorProvider.overrideWithValue(authenticator),
      preparationReminderPlatformProvider.overrideWithValue(
        _FakeReminderPlatform(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('清除远端资料并清除本地备赛数据后，计划/历史/诊断/提醒全部清空', (tester) async {
    final container = await _bootstrap();

    // 预置：备赛计划、助手历史、水平诊断、提醒偏好。
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await container
        .read(assistantHistoryStoreProvider)
        .append(
          'p1',
          AssistantTurn(
            id: 't1',
            planId: 'p1',
            userMessage: '问',
            reply: '答',
            createdAt: DateTime.utc(2026, 6, 29),
            cardStatuses: const {},
          ),
        );
    await container
        .read(levelDiagnosisStoreProvider)
        .save(
          LevelDiagnosis(
            categoryKey: '计算机类',
            diagnosedLevel: ExperienceLevel.beginner,
            effectiveLevel: ExperienceLevel.beginner,
            source: DiagnosisSelectionSource.manualOverride,
            rationale: 'r',
            diagnosedAt: DateTime(2026, 6, 1),
            answers: const {},
          ),
        );
    await container.read(reminderPreferencesProvider.notifier).setEnabled(true);

    expect(
      container.read(preparationPlanRepositoryProvider).list(),
      hasLength(1),
    );
    expect(
      await container.read(assistantHistoryStoreProvider).list('p1'),
      hasLength(1),
    );
    expect(
      (await container.read(levelDiagnosisStoreProvider).get('计算机类')),
      isNotNull,
    );
    expect(container.read(reminderPreferencesProvider).enabled, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const SettingsPage()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除远端资料并清除本地备赛数据'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除'));
    await tester.pumpAndSettle();

    // 计划清空。
    expect(container.read(preparationPlanRepositoryProvider).list(), isEmpty);
    // 助手历史清空。
    expect(
      await container.read(assistantHistoryStoreProvider).list('p1'),
      isEmpty,
    );
    // 诊断清空。
    expect(
      await container.read(levelDiagnosisStoreProvider).get('计算机类'),
      isNull,
    );
    // 提醒恢复默认关闭。
    expect(container.read(reminderPreferencesProvider).enabled, isFalse);
    // 计划列表 provider 刷新后为空。
    expect(container.read(preparationPlanRepositoryProvider).list(), isEmpty);
  });
}
