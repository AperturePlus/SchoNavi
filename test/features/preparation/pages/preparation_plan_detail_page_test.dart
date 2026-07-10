import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/platform/preparation_reminder_platform.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/preparation_reminder.dart';
import 'package:scho_navi/features/preparation/pages/preparation_plan_detail_page.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';
import 'package:scho_navi/features/preparation/providers/preparation_reminder_providers.dart';
import 'package:scho_navi/features/preparation/widgets/preparation_anchor_bar.dart';

PreparationPlan _plan() => PreparationPlan(
  id: 'p1',
  competition: CompetitionSnapshot(
    id: 'c1',
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
  phases: [
    PreparationPhase(
      key: 'team_formation',
      title: '组队',
      startDate: DateTime(2026, 6, 28),
      endDate: DateTime(2026, 7, 5),
      tasks: [
        PreparationTask(
          id: 't1',
          templateKey: 'team_form',
          title: '组建队伍',
          kind: PreparationTaskKind.required,
          estimatedHours: 3,
          dueDate: DateTime(2026, 7, 1),
        ),
      ],
    ),
  ],
  tightSchedule: false,
  overload: false,
  createdAt: DateTime(2026, 6, 28),
  updatedAt: DateTime(2026, 6, 28),
);

class _FakeCalendarPlatform implements PreparationReminderPlatform {
  CalendarAddResult nextResult = CalendarAddResult.success;
  @override
  Future<CalendarAddResult> addDeadlineEvent(
    CalendarDeadlineEvent event,
  ) async => nextResult;
  @override
  bool get isSupported => true;
  @override
  Future<void> syncSnapshot(PreparationReminderSnapshot snapshot) async {}
  @override
  Future<void> updateSchedule(ReminderPreferences preferences) async {}
  @override
  Future<ReminderNotificationStatus> getNotificationStatus() async =>
      ReminderNotificationStatus.granted;
  @override
  Future<ReminderNotificationStatus> requestNotificationPermission() async =>
      ReminderNotificationStatus.granted;
  @override
  Future<bool> pinWidget() async => false;
  @override
  Future<void> openNotificationSettings() async {}
  @override
  Future<String?> takeInitialRoute() async => null;
  @override
  void setRouteHandler(ReminderRouteHandler? handler) {}
}

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

Future<void> _changeTargetDateToNextMonthDay(
  WidgetTester tester,
  int day,
) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  await tester.tap(find.text('调整目标日期'));
  await tester.pumpAndSettle();
  await _tapNextPickerMonth(tester);
  await _tapPickerDay(tester, day);
  await tester.tap(find.text('确认'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async => SharedPreferences.setMockInitialValues({}));

  /// Bootstraps a real ProviderContainer with the SharedPreferences instance
  /// so [preparationPlanRepositoryProvider] (→ localStoreProvider →
  /// sharedPreferencesProvider) resolves. Mirrors the convention used by
  /// preparation_plan_form_page_test.dart.
  Future<ProviderContainer> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('渲染倒计时+进度+时间轴+任务', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    expect(find.textContaining('剩余'), findsOneWidget);
    expect(find.text('组队'), findsOneWidget);
    expect(find.text('组建队伍'), findsOneWidget);
  });

  testWidgets('仓库外部保存后详情页自动刷新任务列表', (t) async {
    final container = await bootstrap();
    final repo = container.read(preparationPlanRepositoryProvider);
    await repo.save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('组建队伍'), findsOneWidget);
    expect(find.text('助手新增任务'), findsNothing);

    final latest = repo.findById('p1')!;
    final phase = latest.phases.single;
    await repo.save(
      latest.copyWith(
        phases: [
          phase.copyWith(
            tasks: [
              ...phase.tasks,
              PreparationTask(
                id: 't_external',
                title: '助手新增任务',
                kind: PreparationTaskKind.userAdded,
                estimatedHours: 1,
                dueDate: DateTime(2026, 7, 2),
              ),
            ],
          ),
        ],
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('助手新增任务'), findsOneWidget);
    expect(find.text('组队 · 2 项任务'), findsOneWidget);
  });

  testWidgets('小组件直达详情页时 AppBar 返回到我的备赛列表', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    final router = GoRouter(
      initialLocation: '/preparation-plans/p1',
      routes: [
        GoRoute(
          path: '/preparation-plans',
          builder: (_, _) => const Scaffold(body: Text('我的备赛列表')),
        ),
        GoRoute(
          path: '/preparation-plans/:id',
          builder: (_, state) =>
              PreparationPlanDetailPage(planId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();

    final backButton = find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('返回'),
    );
    expect(backButton, findsOneWidget);

    await t.tap(backButton);
    await t.pumpAndSettle();

    expect(find.text('我的备赛列表'), findsOneWidget);
  });

  testWidgets('勾选任务标记完成', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox));
    await t.pumpAndSettle();
    final plan = container
        .read(preparationPlanRepositoryProvider)
        .findById('p1')!;
    expect(plan.phases[0].tasks[0].completed, isTrue);
  });

  testWidgets('删除必做任务被阻止', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    // 必做任务的删除按钮不存在或禁用
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('过去阶段添加任务打开 DatePicker 不断言', (t) async {
    // 阶段 endDate 与任务 dueDate 均在今天之前；showDatePicker 会断言
    // initialDate >= firstDate，未钳制时会抛 assertion。
    final pastPlan = PreparationPlan(
      id: 'pPast',
      competition: CompetitionSnapshot(
        id: 'c1',
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
      phases: [
        PreparationPhase(
          key: 'past_phase',
          title: '已过期阶段',
          // 故意设在很早以前，确保 endDate < today。
          startDate: DateTime(2020, 1, 1),
          endDate: DateTime(2020, 1, 7),
          tasks: [
            PreparationTask(
              id: 'pt1',
              templateKey: 'past_task',
              title: '过期任务',
              kind: PreparationTaskKind.optional,
              estimatedHours: 2,
              dueDate: DateTime(2020, 1, 5),
            ),
          ],
        ),
      ],
      tightSchedule: false,
      overload: false,
      createdAt: DateTime(2020, 1, 1),
      updatedAt: DateTime(2020, 1, 1),
    );
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(pastPlan);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'pPast')),
      ),
    );
    await t.pumpAndSettle();
    // 新增的关键日期卡片把任务清单推到视口外；拖动 ListView 让「添加任务」可见。
    await t.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await t.pumpAndSettle();
    await t.tap(find.text('添加任务'), warnIfMissed: false);
    await t.pumpAndSettle();
    // 点击日期行触发 showDatePicker；钳制后不应抛断言。
    await t.tap(find.textContaining('截止：'), warnIfMissed: false);
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('详情页渲染锚点条（提交型显示提交+答辩）', (t) async {
    final plan = _plan().copyWith(
      timelineType: CompetitionTimelineType.submission,
      defenseDate: DateTime(2026, 9, 10),
    );
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(plan);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PreparationAnchorBar),
        matching: find.textContaining('提交'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PreparationAnchorBar),
        matching: find.textContaining('答辩'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('defense_prep 阶段添加任务日期区间为提交后', (t) async {
    // defense_prep 任务应在 [targetDate+1, defenseDate] 区间；
    // 阶段 endDate 默认在答辩前，钳制后打开 DatePicker 不应抛断言。
    final plan = _plan().copyWith(
      timelineType: CompetitionTimelineType.submission,
      targetDate: DateTime(2026, 9, 1),
      defenseDate: DateTime(2026, 9, 10),
      phases: [
        PreparationPhase(
          key: 'defense_prep',
          title: '答辩准备',
          startDate: DateTime(2026, 9, 2),
          endDate: DateTime(2026, 9, 8),
          tasks: const [],
        ),
      ],
    );
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(plan);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('添加任务'));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('截止：'));
    await t.pump();
    // 钳制后初始 dueDate 落在 [targetDate+1, defenseDate]，无断言。
    expect(t.takeException(), isNull);
  });

  testWidgets('AppBar 无日历图标，更多菜单含调整目标日期', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();

    expect(find.byTooltip('修改目标日期'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.event_outlined),
      ),
      findsNothing,
    );
    // 顶部三点按钮打开自定义更多菜单（bottom sheet）。
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('调整目标日期'), findsOneWidget);
    expect(find.text('归档计划'), findsOneWidget);
    expect(find.text('删除计划'), findsOneWidget);
  });

  testWidgets('详情页渲染 AI 助手浮动按钮并打开抽屉', (t) async {
    final container = await bootstrap();
    await container.read(preparationPlanRepositoryProvider).save(_plan());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();
    final fab = find.byIcon(Icons.auto_awesome);
    expect(fab, findsOneWidget);
    await t.tap(fab);
    await t.pumpAndSettle();
    // 抽屉标题与输入条出现。
    expect(find.text('竞航小助手'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  // ── 提交型重排：仅前置阶段被重排，defense_prep 阶段及其未完成任务不变 ────
  // spec §4.5：提交型修改 targetDate 只重排提交前阶段（不重排 defense_prep）。
  // 此前没有测试覆盖 _changeTargetDate 里的 `p.key != 'defense_prep'` 过滤，
  // 若有人误把 defense_prep 拉回前置窗口会静默破坏双段不变量。这里直接调用
  // 抽取出的纯单元 PreparationPlanDetailRescheduler 验证该过滤。
  test('提交型重排仅前置阶段：defense_prep 边界与未完成任务 dueDate 不变', () {
    final today = DateTime(2026, 6, 28);
    final originalTarget = DateTime(2026, 9, 1);
    final defenseDate = DateTime(2026, 9, 10);
    final defenseStart = DateTime(2026, 9, 2);
    final defenseEnd = DateTime(2026, 9, 8);
    final defenseTaskDue = DateTime(2026, 9, 6);

    final plan = PreparationPlan(
      id: 'pSub',
      competition: CompetitionSnapshot(
        id: 'c1',
        name: '挑战杯',
        category: '综合类',
        rulesSummary: CompetitionRulesSummary(
          signupTime: '',
          contestTime: '',
          teamSize: '',
          format: '',
          organizer: '',
          officialUrl: null,
        ),
      ),
      targetDate: originalTarget,
      timelineType: CompetitionTimelineType.submission,
      defenseDate: defenseDate,
      weeklyCommitment: WeeklyCommitment.hours6to10,
      experienceLevel: ExperienceLevel.beginner,
      status: PreparationPlanStatus.active,
      phases: [
        PreparationPhase(
          key: 'proposal_writing',
          title: '选题与提案',
          startDate: DateTime(2026, 7, 6),
          endDate: DateTime(2026, 8, 10),
          tasks: [
            PreparationTask(
              id: 'pw1',
              templateKey: 'draft_proposal',
              title: '撰写提案初稿',
              kind: PreparationTaskKind.required,
              estimatedHours: 8,
              dueDate: DateTime(2026, 8, 5),
            ),
          ],
        ),
        PreparationPhase(
          key: 'defense_prep',
          title: '答辩准备',
          startDate: defenseStart,
          endDate: defenseEnd,
          tasks: [
            PreparationTask(
              id: 'dp1',
              templateKey: 'slides',
              title: '制作答辩幻灯片',
              kind: PreparationTaskKind.required,
              estimatedHours: 6,
              dueDate: defenseTaskDue,
            ),
          ],
        ),
      ],
      createdAt: DateTime(2026, 6, 28),
      updatedAt: DateTime(2026, 6, 28),
    );

    // 把目标日期提前到 2026-08-15，前置窗口收紧。
    final newTarget = DateTime(2026, 8, 15);
    final result =
        PreparationPlanDetailRescheduler.rescheduleForTargetDateChange(
          plan: plan,
          newTargetDate: newTarget,
          today: today,
        );

    // 提取重排后的阶段（顺序应与原 plan 一致：proposal_writing 在前，defense_prep 在后）。
    final newProposal = result.phases.firstWhere(
      (p) => p.key == 'proposal_writing',
    );
    final newDefense = result.phases.firstWhere((p) => p.key == 'defense_prep');

    // 1) defense_prep 阶段边界完全不变。
    expect(newDefense.startDate, defenseStart);
    expect(newDefense.endDate, defenseEnd);
    // 2) defense_prep 未完成任务 dueDate 不变，仍落在 [targetDate+1, defenseDate]。
    expect(newDefense.tasks.single.dueDate, defenseTaskDue);
    expect(newDefense.tasks.single.dueDate.isAfter(originalTarget), isTrue);
    expect(
      newDefense.tasks.single.dueDate.isBefore(defenseDate) ||
          newDefense.tasks.single.dueDate == defenseDate,
      isTrue,
    );

    // 3) 前置阶段 proposal_writing 被重排：endDate 改变，且新窗口落在
    //    [today, newTargetDate] 内（证明它被收进新的前置窗口而非保持原样）。
    expect(newProposal.endDate, isNot(DateTime(2026, 8, 10)));
    expect(
      !newProposal.endDate.isBefore(today),
      isTrue,
      reason: '前置阶段 endDate 不应早于 today',
    );
    expect(
      !newProposal.endDate.isAfter(newTarget),
      isTrue,
      reason: '前置阶段 endDate 不应晚于新 targetDate',
    );
    // 前置阶段未完成任务 dueDate 也被重排到新 endDate（钳制到新窗口内）。
    expect(newProposal.tasks.single.dueDate, isNot(DateTime(2026, 8, 5)));
    expect(
      !newProposal.tasks.single.dueDate.isBefore(today) &&
          !newProposal.tasks.single.dueDate.isAfter(newTarget),
      isTrue,
    );

    // 4) 提交型不应改动 eventEndDate（本例无 eventEndDate，仍为 null）。
    expect(result.eventEndDate, isNull);
  });

  testWidgets('调整目标日期后报名截止不再早于目标日期则清空', (t) async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    final originalTarget = DateTime(now.year, now.month + 2, 20);
    final newTarget = DateTime(nextMonth.year, nextMonth.month, 10);
    final registrationDeadline = DateTime(nextMonth.year, nextMonth.month, 15);

    final container = await bootstrap();
    await container
        .read(preparationPlanRepositoryProvider)
        .save(
          _plan().copyWith(
            targetDate: originalTarget,
            registrationDeadline: registrationDeadline,
          ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();

    await _changeTargetDateToNextMonthDay(t, newTarget.day);

    final saved = container
        .read(preparationPlanRepositoryProvider)
        .findById('p1')!;
    expect(saved.targetDate, newTarget);
    expect(saved.registrationDeadline, isNull);
    expect(find.text('目标日期已更新，报名截止已清空，请重新选择'), findsOneWidget);
  });

  testWidgets('调整目标日期后报名截止仍早于目标日期则保留', (t) async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);
    final originalTarget = DateTime(now.year, now.month + 2, 20);
    final newTarget = DateTime(nextMonth.year, nextMonth.month, 10);
    final registrationDeadline = DateTime(nextMonth.year, nextMonth.month, 8);

    final container = await bootstrap();
    await container
        .read(preparationPlanRepositoryProvider)
        .save(
          _plan().copyWith(
            targetDate: originalTarget,
            registrationDeadline: registrationDeadline,
          ),
        );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
      ),
    );
    await t.pumpAndSettle();

    await _changeTargetDateToNextMonthDay(t, newTarget.day);

    final saved = container
        .read(preparationPlanRepositoryProvider)
        .findById('p1')!;
    expect(saved.targetDate, newTarget);
    expect(saved.registrationDeadline, registrationDeadline);
    expect(find.text('目标日期已更新，未完成任务已重新排期'), findsOneWidget);
  });

  // ── 加入系统日历集成（Task 6） ──────────────────────────────────────────────
  PreparationPlan deadlinePlan({DateTime? registrationDeadline}) =>
      _plan().copyWith(registrationDeadline: registrationDeadline);

  testWidgets('点加入日历成功显示已加入系统日历', (t) async {
    final fake = _FakeCalendarPlatform()
      ..nextResult = CalendarAddResult.success;
    final container = await bootstrap();
    await container
        .read(preparationPlanRepositoryProvider)
        .save(deadlinePlan(registrationDeadline: DateTime(2026, 8, 15)));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ProviderScope(
          overrides: [
            preparationReminderPlatformProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deadline-add-calendar')).first);
    await t.pumpAndSettle();
    expect(find.text('已加入系统日历'), findsOneWidget);
  });

  testWidgets('unsupported 时显示当前设备不支持', (t) async {
    final fake = _FakeCalendarPlatform()
      ..nextResult = CalendarAddResult.unsupported;
    final container = await bootstrap();
    await container
        .read(preparationPlanRepositoryProvider)
        .save(deadlinePlan(registrationDeadline: DateTime(2026, 8, 15)));
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ProviderScope(
          overrides: [
            preparationReminderPlatformProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(home: PreparationPlanDetailPage(planId: 'p1')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('deadline-add-calendar')).first);
    await t.pumpAndSettle();
    expect(find.text('当前设备不支持，请手动添加'), findsOneWidget);
  });
}
