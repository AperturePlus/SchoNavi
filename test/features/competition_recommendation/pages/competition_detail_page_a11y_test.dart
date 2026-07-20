import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/repositories/competition_catalog_repository.dart';
import 'package:scho_navi/features/competition_recommendation/pages/competition_detail_page.dart';

const _competition = RecommendedCompetition(
  id: 'comp_icpc',
  name: 'ACM-ICPC 国际大学生程序设计竞赛',
  category: '计算机类',
  level: '国际级',
  tags: ['程序设计', '团队赛'],
  teamSize: '3 人团队',
  signupTime: '以官网通知为准',
  contestTime: '通常每年 9-12 月',
  format: '上机编程解题',
  organizer: 'ICPC 基金会',
  officialUrl: 'https://icpc.global',
  reason: '方向匹配。',
  preparationTips: ['训练算法与数据结构'],
  limitations: ['以官网通知为准。'],
  matchScore: 0.9,
);

class _FakeCatalogRepository extends CompetitionCatalogRepository {
  @override
  RecommendedCompetition? findById(String id) =>
      id == _competition.id ? _competition : null;
}

void main() {
  setUp(() async => SharedPreferences.setMockInitialValues({}));

  testWidgets('详情页 375x800 / textScale 1.5 / 深色主题下不溢出', (tester) async {
    addTearDown(() {
      tester.platformDispatcher.clearAllTestValues();
      tester.view.reset();
    });

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(375, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        competitionCatalogRepositoryProvider.overrideWithValue(
          _FakeCatalogRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    // 页面内部已有 ListView，不额外包 SingleChildScrollView，确保溢出能暴露。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: const CompetitionDetailPage(competitionId: 'comp_icpc'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CompetitionDetailPage), findsOneWidget);
    expect(find.textContaining('ACM-ICPC'), findsWidgets);
  });
}
