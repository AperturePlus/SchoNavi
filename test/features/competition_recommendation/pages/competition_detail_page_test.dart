import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/data/fixtures/competition_catalog_repository_impl.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/features/competition_recommendation/pages/competition_detail_page.dart';
import 'package:scho_navi/features/preparation/pages/preparation_plan_form_page.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';

const _catalog = StaticCompetitionCatalogRepository();

GoRouter _routerWithDetailAndForm() {
  const catalog = _catalog;
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const CompetitionDetailPage(competitionId: 'comp_icpc'),
      ),
      GoRoute(
        path: '/preparation-plans/new',
        builder: (_, state) {
          final cid = state.uri.queryParameters['competitionId'] ?? '';
          final base = catalog.findById(cid);
          return PreparationPlanFormPage(
            competition: CompetitionSnapshot(
              id: base?.id ?? cid,
              name: base?.name ?? '',
              category: base?.category ?? '',
              rulesSummary: CompetitionRulesSummary(
                signupTime: base?.signupTime ?? '',
                contestTime: base?.contestTime ?? '',
                teamSize: base?.teamSize ?? '',
                format: base?.format ?? '',
                organizer: base?.organizer ?? '',
                officialUrl: base?.officialUrl,
              ),
            ),
          );
        },
      ),
      GoRoute(
        path: '/preparation-plans/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['id']}')),
      ),
    ],
  );
}

PreparationPlan _activePlan() => PreparationPlan(
  id: 'p1',
  competition: CompetitionSnapshot(
    id: 'comp_icpc',
    name: 'ACM-ICPC',
    category: '计算机类',
    rulesSummary: CompetitionRulesSummary(
      signupTime: '',
      contestTime: '',
      teamSize: '',
      format: '',
      organizer: '',
      officialUrl: null,
    ),
  ),
  targetDate: DateTime(2026, 9, 1),
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.beginner,
  status: PreparationPlanStatus.active,
  phases: const [],
  tightSchedule: false,
  overload: false,
  createdAt: DateTime(2026, 6, 28),
  updatedAt: DateTime(2026, 6, 28),
);

const _markdownRecommended = RecommendedCompetition(
  id: 'comp_icpc',
  name: '中国高校计算机大赛',
  category: '计算机类',
  level: '国家级',
  tags: [],
  teamSize: '',
  signupTime: '',
  contestTime: '',
  format: '',
  organizer: '',
  officialUrl: null,
  reason: '**大数据挑战赛**：重数据处理、验证和复现。',
  preparationTips: [],
  limitations: [],
  matchScore: 0.86,
);

void main() {
  setUp(() async => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('从目录渲染详情，含赛制信息与官网', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CompetitionDetailPage(competitionId: 'comp_icpc'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('ACM-ICPC 国际大学生程序设计竞赛'), findsWidgets);
    expect(find.text('赛制信息'), findsOneWidget);
    expect(find.text('主办方'), findsOneWidget);
    expect(find.text('访问官网'), findsOneWidget);
  });

  testWidgets('未知 id 显示未找到', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CompetitionDetailPage(competitionId: 'nope'),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('未找到'), findsOneWidget);
  });

  testWidgets('未知 id 空态 AppBar 标题为「竞赛详情」', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CompetitionDetailPage(competitionId: 'nope'),
        ),
      ),
    );
    await t.pumpAndSettle();

    final appBar = t.widget<AppBar>(find.byType(AppBar));
    final title = appBar.title;
    expect(title, isA<Text>());
    expect((title as Text).data, '竞赛详情');
  });

  testWidgets('传入 recommended 时显示 AI 补充提示', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CompetitionDetailPage(
            competitionId: 'comp_icpc',
            recommended: null, // 仅目录；AI 区块测试见 widget 测试 B3
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    // 目录基底 limitations 为通用提示，preparationTips 非空 -> AI 区块应显示
    expect(find.text('AI 补充提示'), findsOneWidget);
  });

  testWidgets('竞赛 reason 使用 Markdown 渲染', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: CompetitionDetailPage(
            competitionId: 'comp_icpc',
            recommended: _markdownRecommended,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.byType(GptMarkdown), findsWidgets);
    expect(find.text('**大数据挑战赛**：重数据处理、验证和复现。'), findsNothing);
  });

  testWidgets('无进行中计划显示"开始备赛"且可点击进入表单', (t) async {
    final container = await bootstrap();
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _routerWithDetailAndForm()),
      ),
    );
    await t.pumpAndSettle();
    // 备赛按钮在列表底部，需滚动到可见后才能交互。
    await t.scrollUntilVisible(
      find.text('开始备赛'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    final btn = find.text('开始备赛');
    expect(btn, findsOneWidget);
    await t.tap(btn);
    await t.pumpAndSettle();
    // 进入表单页：断言时间模型字段标签可见
    expect(find.text('时间模型'), findsOneWidget);
  });

  testWidgets('有进行中计划显示"继续备赛"', (t) async {
    final container = await bootstrap();
    // 预存一个 active plan for comp_icpc
    await container.read(preparationPlanRepositoryProvider).save(_activePlan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: _routerWithDetailAndForm()),
      ),
    );
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('继续备赛'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(find.text('继续备赛'), findsOneWidget);
  });
}
