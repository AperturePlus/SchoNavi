import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/preparation_config.dart';
import 'package:scho_navi/domain/entities/level_diagnosis.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_config_repository.dart';
import 'package:scho_navi/domain/repositories/preparation_level_diagnoser.dart';
import 'package:scho_navi/features/preparation/pages/preparation_plan_form_page.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';

CompetitionSnapshot _comp() => CompetitionSnapshot(
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
);

CompetitionSnapshot _genericComp() => CompetitionSnapshot(
  id: 'comp_unknown',
  name: '某竞赛',
  category: '综合类',
  rulesSummary: CompetitionRulesSummary(
    signupTime: '',
    contestTime: '',
    teamSize: '',
    format: '',
    organizer: '',
    officialUrl: null,
  ),
);

/// 永远返回 Success(intermediate) 的假诊断器。
class _FakeDiagnoser implements PreparationLevelDiagnoser {
  const _FakeDiagnoser();

  @override
  Future<Result<LevelDiagnosisSuggestion>> diagnose(
    LevelDiagnosisRequest request,
  ) async {
    return const Success(
      LevelDiagnosisSuggestion(
        level: ExperienceLevel.intermediate,
        rationale: '参加过校级赛，建议进阶排期',
        suggestion: '每周加练 2 套真题',
      ),
    );
  }
}

/// 永远返回 Failure 的假诊断器（模拟离线 / LLM 不可用）。
class _FailingDiagnoser implements PreparationLevelDiagnoser {
  @override
  Future<Result<LevelDiagnosisSuggestion>> diagnose(
    LevelDiagnosisRequest request,
  ) async {
    return const Failure(NetworkException());
  }
}

class _CapturingDiagnoser implements PreparationLevelDiagnoser {
  LevelDiagnosisRequest? lastRequest;

  @override
  Future<Result<LevelDiagnosisSuggestion>> diagnose(
    LevelDiagnosisRequest request,
  ) async {
    lastRequest = request;
    return const Success(
      LevelDiagnosisSuggestion(
        level: ExperienceLevel.intermediate,
        rationale: '英文配置选项已提交',
      ),
    );
  }
}

class _FakeConfigRepository implements PreparationConfigRepository {
  const _FakeConfigRepository(this.config);

  final PreparationConfig config;

  @override
  Future<PreparationConfig> fetch() async => config;
}

/// 表单在 ListView 中懒加载，需较高视口让全部区段进入布局。
/// 统一在 setUp 中放大视口；用不到时无副作用。
const _testViewSize = Size(420, 1400);

String _fmt(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Future<void> _tapNextPickerMonth(WidgetTester tester) async {
  await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right).last);
  await tester.pumpAndSettle();
}

Future<void> _tapPickerDay(WidgetTester tester, int day) async {
  await tester.tap(
    find
        .ancestor(of: find.text('$day'), matching: find.byType(GestureDetector))
        .last,
  );
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<ProviderContainer> bootstrap({
    PreparationLevelDiagnoser? diagnoser,
    PreparationConfigRepository? configRepository,
    Map<String, Object> initialStore = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialStore);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (configRepository != null)
          preparationConfigRepositoryProvider.overrideWithValue(
            configRepository,
          ),
        if (diagnoser != null)
          preparationLevelDiagnoserProvider.overrideWithValue(diagnoser),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpForm(
    WidgetTester tester,
    ProviderContainer container,
    CompetitionSnapshot competition,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _testViewSize;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: PreparationPlanFormPage(competition: competition),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('渲染时间模型 + 每周投入 + 当前水平 + 创建按钮', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _comp());
    expect(find.text('时间模型'), findsOneWidget);
    expect(find.text('每周投入'), findsOneWidget);
    expect(find.text('当前水平'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '创建备赛计划'), findsOneWidget);
  });

  testWidgets('ICPC 默认预选窗口型并展示区间入口', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _comp());
    expect(find.text('选择比赛起止日期'), findsOneWidget);
  });

  testWidgets('未知赛事默认预选提交型并展示 DDL/答辩入口', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _genericComp());
    expect(find.text('选择提交 DDL 与答辩'), findsOneWidget);
  });

  testWidgets('选窗口型后日期入口变为比赛起止', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _genericComp());
    await tester.tap(find.text('窗口型'));
    await tester.pumpAndSettle();
    expect(find.text('选择比赛起止日期'), findsOneWidget);
  });

  testWidgets('选提交型后日期入口变为 DDL 与答辩', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _comp());
    await tester.tap(find.text('提交型'));
    await tester.pumpAndSettle();
    expect(find.text('选择提交 DDL 与答辩'), findsOneWidget);
  });

  testWidgets('未选目标日期时创建按钮提示请选择', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _comp());
    await tester.tap(find.widgetWithText(FilledButton, '创建备赛计划'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请选择'), findsOneWidget);
  });

  // ── Step 2 水平诊断（P3.4）──────────────────────────────────────────────

  testWidgets('无画像时显示诊断两问与诊断按钮', (tester) async {
    final container = await bootstrap(diagnoser: const _FakeDiagnoser());
    await pumpForm(tester, container, _comp());
    expect(find.text('水平诊断'), findsOneWidget);
    expect(find.textContaining('参赛经历'), findsOneWidget);
    expect(find.textContaining('领域熟悉度'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '诊断'), findsOneWidget);
  });

  testWidgets('英文配置选项显示中文但诊断仍提交原始 code', (tester) async {
    final diagnoser = _CapturingDiagnoser();
    final container = await bootstrap(
      diagnoser: diagnoser,
      configRepository: const _FakeConfigRepository(
        PreparationConfig(
          categoryAliases: {},
          timelineDefaults: {},
          priorExperienceOptions: ['beginner', 'intermediate', 'experienced'],
          domainFamiliarityOptions: ['low', 'medium', 'high'],
        ),
      ),
    );
    await pumpForm(tester, container, _comp());

    expect(find.text('从没参加'), findsOneWidget);
    expect(find.text('参加过未获奖'), findsOneWidget);
    expect(find.text('获得校级以上奖'), findsOneWidget);
    expect(find.text('不熟'), findsOneWidget);
    expect(find.text('一般'), findsOneWidget);
    expect(find.text('熟悉'), findsOneWidget);
    expect(find.text('beginner'), findsNothing);
    expect(find.text('low'), findsNothing);

    await tester.tap(find.text('获得校级以上奖'));
    await tester.tap(find.text('熟悉'));
    await tester.tap(find.widgetWithText(FilledButton, '诊断'));
    await tester.pumpAndSettle();

    final answers = {
      for (final answer in diagnoser.lastRequest!.answers)
        answer.questionKey: answer.answer,
    };
    expect(answers['prior_experience'], 'experienced');
    expect(answers['domain_familiarity'], 'high');
  });

  testWidgets('点诊断后展示 AI 卡 + 接受 + 手动改档', (tester) async {
    final container = await bootstrap(diagnoser: const _FakeDiagnoser());
    await pumpForm(tester, container, _comp());
    await tester.tap(find.widgetWithText(FilledButton, '诊断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('AI 建议'), findsOneWidget);
    expect(find.textContaining('参加过校级赛'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '接受'), findsOneWidget);
    expect(find.textContaining('手动改档'), findsOneWidget);
  });

  testWidgets('接受诊断后写入 store 并设置 effectiveLevel', (tester) async {
    final container = await bootstrap(diagnoser: const _FakeDiagnoser());
    await pumpForm(tester, container, _comp());
    await tester.tap(find.widgetWithText(FilledButton, '诊断'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '接受'));
    await tester.pumpAndSettle();
    final store = container.read(levelDiagnosisStoreProvider);
    final saved = await store.get('计算机类');
    expect(saved, isNotNull);
    expect(saved!.effectiveLevel, ExperienceLevel.intermediate);
    expect(saved.source, DiagnosisSelectionSource.aiAccepted);
    // 当前水平 SegmentedButton 已选进阶。
    await tester.scrollUntilVisible(
      find.text('当前水平'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    final intermediate = find.ancestor(
      of: find.text('进阶'),
      matching: find.byType(SegmentedButton<ExperienceLevel>),
    );
    expect(intermediate, findsOneWidget);
  });

  testWidgets('诊断失败显示错误态并允许手动改档继续', (tester) async {
    final container = await bootstrap(diagnoser: _FailingDiagnoser());
    await pumpForm(tester, container, _comp());
    await tester.tap(find.widgetWithText(FilledButton, '诊断'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.textContaining('诊断失败'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('当前水平'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    final intermediate = find.ancestor(
      of: find.text('进阶'),
      matching: find.byType(SegmentedButton<ExperienceLevel>),
    );
    expect(intermediate, findsOneWidget);
  });

  testWidgets('有画像时跳过问答展示摘要 + 重新诊断 + 临时改档', (tester) async {
    final existing = LevelDiagnosis(
      categoryKey: '计算机类',
      diagnosedLevel: ExperienceLevel.experienced,
      effectiveLevel: ExperienceLevel.experienced,
      source: DiagnosisSelectionSource.aiAccepted,
      rationale: '老选手',
      suggestion: null,
      diagnosedAt: DateTime.utc(2026, 6, 1),
      answers: const {'prior_experience': '校级以上奖', 'domain_familiarity': '熟悉'},
    );
    final container = await bootstrap(
      diagnoser: const _FakeDiagnoser(),
      initialStore: {
        'level_diagnosis.v1': jsonEncode({'计算机类': existing.toJson()}),
      },
    );
    await pumpForm(tester, container, _comp());
    expect(find.textContaining('参赛经历'), findsNothing);
    expect(find.textContaining('已按你的'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重新诊断'), findsOneWidget);
    expect(find.textContaining('临时改档'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('当前水平'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    final exp = find.ancestor(
      of: find.text('老手'),
      matching: find.byType(SegmentedButton<ExperienceLevel>),
    );
    expect(exp, findsOneWidget);
  });

  testWidgets('临时改档不覆盖 store 中的画像', (tester) async {
    final existing = LevelDiagnosis(
      categoryKey: '计算机类',
      diagnosedLevel: ExperienceLevel.experienced,
      effectiveLevel: ExperienceLevel.experienced,
      source: DiagnosisSelectionSource.aiAccepted,
      rationale: '老选手',
      suggestion: null,
      diagnosedAt: DateTime.utc(2026, 6, 1),
      answers: const {'prior_experience': '校级以上奖', 'domain_familiarity': '熟悉'},
    );
    final container = await bootstrap(
      diagnoser: const _FakeDiagnoser(),
      initialStore: {
        'level_diagnosis.v1': jsonEncode({'计算机类': existing.toJson()}),
      },
    );
    await pumpForm(tester, container, _comp());
    await tester.scrollUntilVisible(
      find.text('新手'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('新手'));
    await tester.pumpAndSettle();
    final store = container.read(levelDiagnosisStoreProvider);
    final saved = await store.get('计算机类');
    expect(saved!.effectiveLevel, ExperienceLevel.experienced);
  });

  testWidgets('报名截止行显示并可打开', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _comp());
    expect(find.textContaining('报名截止'), findsOneWidget);
  });

  testWidgets('提交截止提前到报名截止之前时清空报名截止', (tester) async {
    final container = await bootstrap();
    await pumpForm(tester, container, _genericComp());

    final today = DateTime.now();
    final pickerMonth = DateTime(today.year, today.month + 1);
    final firstDeadline = DateTime(pickerMonth.year, pickerMonth.month, 12);
    final defense = DateTime(pickerMonth.year, pickerMonth.month, 14);
    final registrationDeadline = DateTime(
      pickerMonth.year,
      pickerMonth.month,
      10,
    );
    final earlierDeadline = DateTime(pickerMonth.year, pickerMonth.month, 8);

    await tester.tap(find.text('选择提交 DDL 与答辩'));
    await tester.pumpAndSettle();
    await _tapNextPickerMonth(tester);
    await _tapPickerDay(tester, firstDeadline.day);
    await _tapPickerDay(tester, defense.day);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(
      find.text('DDL ${_fmt(firstDeadline)} · 答辩 ${_fmt(defense)}'),
      findsOneWidget,
    );

    await tester.tap(find.text('可选，设置后可一键加入日历'));
    await tester.pumpAndSettle();
    await _tapNextPickerMonth(tester);
    await _tapPickerDay(tester, registrationDeadline.day);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text(_fmt(registrationDeadline)), findsOneWidget);

    await tester.tap(
      find.text('DDL ${_fmt(firstDeadline)} · 答辩 ${_fmt(defense)}'),
    );
    await tester.pumpAndSettle();
    await _tapNextPickerMonth(tester);
    await _tapPickerDay(tester, earlierDeadline.day);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(find.text('可选，设置后可一键加入日历'), findsOneWidget);
    expect(find.text(_fmt(registrationDeadline)), findsNothing);
  });
}
