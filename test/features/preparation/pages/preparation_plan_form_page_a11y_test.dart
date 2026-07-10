import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/theme/app_theme.dart';
import 'package:scho_navi/domain/entities/preparation_config.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_config_repository.dart';
import 'package:scho_navi/features/preparation/pages/preparation_plan_form_page.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';

/// 无障碍验证（A11/B6 教训）：375 宽 + textScale 1.5 + 深色主题下，
/// 表单页（其内部已是 ListView）不应产生 overflow / RenderFlex 异常。
///
/// 本测试 *不* 在外部再套一层 SingleChildScrollView——那只是掩盖问题，
/// 不暴露真正的溢出。我们直接 pump 页面本体并断言 `takeException()` 为 null。
CompetitionSnapshot _comp() => CompetitionSnapshot(
  id: 'comp_icpc',
  name: 'ACM-ICPC 亚洲区域赛',
  category: '计算机类',
  rulesSummary: CompetitionRulesSummary(
    signupTime: '',
    contestTime: '',
    teamSize: '',
    format: '',
    organizer: '',
    officialUrl: null,
  ),
);

class _FakeConfigRepository implements PreparationConfigRepository {
  const _FakeConfigRepository();

  @override
  Future<PreparationConfig> fetch() async => const PreparationConfig(
    categoryAliases: {},
    timelineDefaults: {'comp_icpc': CompetitionTimelineType.eventWindow},
    priorExperienceOptions: ['从没参加', '参加过未获奖', '获得校级以上奖'],
    domainFamiliarityOptions: ['不熟', '一般', '熟悉'],
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        preparationConfigRepositoryProvider.overrideWithValue(
          const _FakeConfigRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('375x800 + 1.5x + dark 无 overflow', (tester) async {
    // 固定视口与字号缩放，模拟小屏 + 大字 + 深色场景。
    // 注意：新 API 用 platformDispatcher.textScaleFactorTestValue（旧 view.textScaleFactor 已移除）。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(375, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      tester.platformDispatcher.clearAllTestValues();
      tester.view.reset();
    });

    final container = await bootstrap();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeMode.dark,
          home: PreparationPlanFormPage(competition: _comp()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 关键断言：无任何未处理异常（含 RenderFlex overflow）。
    expect(tester.takeException(), isNull);
    // 烟雾：页面真的渲染了关键字段。
    expect(find.text('时间模型'), findsOneWidget);
    // 表单较高，底部按钮需滚动进入视口后再断言。
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '创建备赛计划'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.widgetWithText(FilledButton, '创建备赛计划'), findsOneWidget);
  });
}
