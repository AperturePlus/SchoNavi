import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/competition_recommendation_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/features/home/pages/home_page.dart';

import '../../helpers/fake_favorite_repository.dart';
import '../../helpers/stub_api_dio.dart';

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

class _NoCallCompetitionRepo implements CompetitionRecommendationRepository {
  int calls = 0;
  @override
  Future<Result<CompetitionRecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async {
    calls++;
    return const Failure(ValidationException('should not be called'));
  }
}

Future<Widget> _wrapHome(
  CompetitionRecommendationRepository competitionRepo,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const HomePage())],
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      dioProvider.overrideWithValue(stubDio()),
      apiIdentityDioProvider.overrideWithValue(stubDio()),
      competitionRecommendationRepositoryProvider.overrideWithValue(
        competitionRepo,
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  // 默认 appConfigProvider 未配置 API_BASE_URL，isConfigured == false。

  testWidgets('导师 tab 未配置 API 时提示且不进入对话态', (tester) async {
    final competitionRepo = _NoCallCompetitionRepo();
    await tester.pumpWidget(await _wrapHome(competitionRepo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '医学影像方向 上海交大');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置 API_BASE_URL'), findsOneWidget);
    expect(competitionRepo.calls, 0);
  });

  testWidgets('竞赛 tab 未配置 API 时提示且不进入结果态', (tester) async {
    final competitionRepo = _NoCallCompetitionRepo();
    await tester.pumpWidget(await _wrapHome(competitionRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('竞赛'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '计算机类竞赛 大三');
    await tester.pump();
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置 API_BASE_URL'), findsOneWidget);
    expect(competitionRepo.calls, 0);
  });
}
