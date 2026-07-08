import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/mock/fake_backend.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_assistant.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_repository.dart';
import 'package:scho_navi/features/preparation/widgets/assistant_drawer.dart';
import 'package:scho_navi/features/preparation/widgets/plan_change_card_view.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';

/// 助手抽屉 widget 测试（P4a.5）。
///
/// **Fake plan-id 耦合说明：** FakeBackendAdapter 按 `(method, path)` 精确匹配，
/// assistant 端点默认仅注册 plan id `pp_1`。本测试用 plan id `pp_1` 走默认注册，
/// 避免手动注册（另一用例演示对自定义 plan id 显式注册）。
PreparationPlan _plan({String id = 'pp_1', int revision = 1}) =>
    PreparationPlan(
      id: id,
      competition: CompetitionSnapshot(
        id: 'comp_demo',
        name: 'Demo Cup',
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
      targetDate: DateTime(2026, 5, 30),
      timelineType: CompetitionTimelineType.submission,
      defenseDate: DateTime(2026, 6, 10),
      revision: revision,
      weeklyCommitment: WeeklyCommitment.hours6to10,
      experienceLevel: ExperienceLevel.intermediate,
      status: PreparationPlanStatus.active,
      phases: [
        PreparationPhase(
          key: 'proposal_writing',
          title: '方案撰写',
          startDate: DateTime(2026, 5, 10),
          endDate: DateTime(2026, 5, 22),
          tasks: [
            PreparationTask(
              id: 'task_core_algo',
              title: '核心算法实现',
              kind: PreparationTaskKind.required,
              estimatedHours: 16,
              dueDate: DateTime(2026, 5, 15),
            ),
          ],
        ),
        PreparationPhase(
          key: 'defense_prep',
          title: '答辩准备',
          startDate: DateTime(2026, 5, 31),
          endDate: DateTime(2026, 6, 10),
          tasks: const [],
        ),
      ],
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
    );

Future<ProviderContainer> _bootstrap({
  String planId = 'pp_1',
  bool registerCustomPlanId = false,
  bool savePlan = true,
}) async {
  final prefs = await SharedPreferences.getInstance();
  final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'))
    ..httpClientAdapter = FakeBackendAdapter();
  if (registerCustomPlanId) {
    (dio.httpClientAdapter as FakeBackendAdapter)
        .registerPreparationAssistantHandler(planId: planId);
  }
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(
        AppConfig(
          dataSource: DataSource.http,
          api: const ApiConfig(baseUrl: 'https://fake.local'),
        ),
      ),
      dioProvider.overrideWithValue(dio),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(dio.close);
  if (savePlan) {
    // 仓库 save 新计划要求 revision=0，save 后自增为 1（与 fake 的
    // base_plan_revision=1 对齐）。
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(id: planId, revision: 0));
  }
  return container;
}

Widget _harness(
  ProviderContainer container, {
  String planId = 'pp_1',
  PreparationPlan? plan,
}) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    home: Scaffold(
      body: PreparationAssistantDrawer(
        planId: planId,
        plan: plan ?? _plan(id: planId),
      ),
    ),
  ),
);

void main() {
  setUp(() async => SharedPreferences.setMockInitialValues({}));

  testWidgets('发送消息后渲染 AI 回复与两张改动卡', (t) async {
    final container = await _bootstrap();
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '这周期末考没空，往后挪');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // AI 回复（来自 fake handler 固定文案）。
    expect(find.textContaining('我整理了两项可单独确认的调整'), findsOneWidget);
    // 两张改动卡 summary。
    expect(find.textContaining('移到 5 月 22 日'), findsOneWidget);
    expect(find.textContaining('模拟答辩'), findsOneWidget);
    // 用户消息也渲染。
    expect(find.textContaining('这周期末考没空'), findsOneWidget);
  });

  testWidgets('改动卡渲染 summary + rationale + 状态胶囊 + 启用接受按钮', (t) async {
    final container = await _bootstrap();
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '帮我把算法实现后移');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // rationale 出现（第一张卡）。
    expect(find.textContaining('避开期末考试周'), findsOneWidget);
    // 状态胶囊「待确认」。
    expect(find.text('待确认'), findsWidgets);
    // 接受按钮存在且启用（pending 时可点）。
    final acceptBtn = find.text('接受');
    expect(acceptBtn, findsWidgets);
    final button = t.widget<FilledButton>(
      find.ancestor(of: acceptBtn.first, matching: find.byType(FilledButton)),
    );
    expect(button.enabled, isTrue);
  });

  testWidgets('后端英文 rejected 原因不直接暴露给用户', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
    final adapter = FakeBackendAdapter();
    adapter.register(
      'POST',
      '/api/v1/preparation-plans/pp_1/assistant',
      (options) async => ResponseBody.fromString(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {
            'reply': '好的，我为你细化方案。',
            'change_set': {
              'id': 'cs_rejected',
              'base_plan_revision': 1,
              'cards': [
                {
                  'id': 'cc_rejected',
                  'type': 'add_task',
                  'target_phase_key': 'proposal_writing',
                  'summary': '在基础阶段增加团队契约制定任务',
                  'rationale': '团队契约可避免后续纠纷。',
                  'status': 'rejected',
                  'rejection_code': 'grounding_required',
                  'rejection_reason':
                      'non-advice change cards require at least one grounded source reference',
                },
              ],
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(id: 'pp_1', revision: 0));

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '帮我细化一下方案');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    expect(find.textContaining('non-advice change cards'), findsNothing);
    expect(
      find.text('该建议缺少可校验依据，已被安全拦截，请重新生成。'),
      findsOneWidget,
    );
    expect(
      find.text('本轮没有可直接应用的调整，建议重新生成或换个更具体的需求。'),
      findsOneWidget,
    );
    expect(find.text('接受'), findsNothing);
  });

  testWidgets('自定义 plan id 须显式注册 fake handler', (t) async {
    // plan id 非 pp_1，未注册 → 404 → 走 Failure 分支渲染错误态文案。
    final container = await _bootstrap(planId: 'pp_custom');
    await t.pumpWidget(_harness(container, planId: 'pp_custom'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '随便问');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();
    await t.pump(const Duration(milliseconds: 50));

    // Failure 分支：渲染 P0 错误态（_AssistantErrorView 固定文案）+ 无改动卡。
    expect(find.textContaining('生成失败'), findsOneWidget);
    expect(find.textContaining('移到 5 月 22 日'), findsNothing);
  });

  testWidgets('注册自定义 plan id 后可正常返回卡片', (t) async {
    final container = await _bootstrap(
      planId: 'pp_custom',
      registerCustomPlanId: true,
    );
    await t.pumpWidget(_harness(container, planId: 'pp_custom'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '随便问');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    expect(find.textContaining('我整理了两项可单独确认的调整'), findsOneWidget);
    expect(find.textContaining('移到 5 月 22 日'), findsOneWidget);
  });

  testWidgets('历史轮次渲染（追加后再次打开仍在）', (t) async {
    final container = await _bootstrap();
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '第一轮提问');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // 历史已落盘：重新挂载同 container 的抽屉仍能看到上一轮。
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();
    expect(find.textContaining('第一轮提问'), findsOneWidget);
    expect(find.textContaining('我整理了两项可单独确认的调整'), findsOneWidget);
  });

  // ── P4b.2：接受/拒绝 + stale 检测 ──────────────────────────────────────

  /// 发送消息 → 点接受 addTask 卡 → 仓库写入新计划（新增任务）+ 卡标「已应用」
  /// + 仓库 revision 自 1→2。（moveTask 卡因新日期早于 today 被 validator
  /// 驳回，无接受按钮；仅 addTask 卡可接受。）
  testWidgets('接受 addTask 写回计划并刷新 revision', (t) async {
    final container = await _bootstrap(savePlan: true);
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '加一次模拟答辩');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // 接受前仓库 revision == 1。
    final repo = container.read(preparationPlanRepositoryProvider);
    expect(repo.findById('pp_1')!.revision, 1);

    await t.tap(find.text('接受').first);
    await t.pumpAndSettle();

    // 卡标 applied（状态胶囊 + 按钮文案均出现「已应用」）。
    expect(find.text('已应用'), findsWidgets);
    // 仓库 revision 自增到 2，defense_prep 阶段新增「第二次模拟答辩」任务。
    final saved = repo.findById('pp_1')!;
    expect(saved.revision, 2);
    final defense = saved.phases.firstWhere((p) => p.key == 'defense_prep');
    expect(defense.tasks.any((tk) => tk.title == '第二次模拟答辩'), isTrue);
  });

  /// 接受 deleteTask 卡 → 仓库写入新计划（删除目标任务）+ 卡标「已应用」
  /// + revision 自 1→2。覆盖 moveTask/addTask 之外的第三类改动卡接受路径
  /// （review Finding 2：drawer 级 deleteTask 接受未测）。
  testWidgets('接受 deleteTask 写回计划并刷新 revision', (t) async {
    // 自定义计划：defense_prep 含一个 optional 任务（required 任务不可删）。
    final plan = _plan().copyWith(
      phases: [
        _plan().phases.first,
        PreparationPhase(
          key: 'defense_prep',
          title: '答辩准备',
          startDate: DateTime(2026, 5, 31),
          endDate: DateTime(2026, 6, 10),
          tasks: [
            PreparationTask(
              id: 'task_optional_drill',
              title: '可选模拟答辩',
              kind: PreparationTaskKind.optional,
              estimatedHours: 2,
              dueDate: DateTime(2026, 6, 5),
            ),
          ],
        ),
      ],
    );
    final fakeRepo = _ConflictRepo(plan);
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
    final adapter = FakeBackendAdapter();
    adapter.register(
      'POST',
      '/api/v1/preparation-plans/pp_1/assistant',
      (options) async => ResponseBody.fromString(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {
            'reply': '该任务可删除。',
            'change_set': {
              'id': 'cs_del_1',
              'base_plan_revision': 1,
              'cards': [
                {
                  'id': 'cc_del',
                  'type': 'delete_task',
                  'target_task_id': 'task_optional_drill',
                  'summary': '删除【可选模拟答辩】',
                  'rationale': '与正式答辩重复。',
                  'status': 'pending',
                },
              ],
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
        preparationPlanRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);

    await t.pumpWidget(_harness(container, plan: plan));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '删掉模拟答辩');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    expect(fakeRepo.findById('pp_1')!.revision, 1);
    await t.tap(find.text('接受').first);
    await t.pumpAndSettle();

    expect(fakeRepo.saveCount, 1);
    expect(fakeRepo.findById('pp_1')!.revision, 2);
    final defense = fakeRepo
        .findById('pp_1')!
        .phases
        .firstWhere((p) => p.key == 'defense_prep');
    expect(defense.tasks.any((tk) => tk.id == 'task_optional_drill'), isFalse);
  });

  /// 生成卡片后手工改计划（revision 自 1→2），再点接受 → revision 不匹配 →
  /// 本 change set 剩余 pending 卡全部标 stale（含被点的卡与其它未点的 pending 卡）。
  ///
  /// 用自定义 handler 返回两张可接受 pending 卡（两张 addTask，分别落到
  /// defense_prep 的不同 dueDate），确保 cascade 真正命中多张 pending 卡——
  /// 而非单卡被点后顺便标 stale（review Finding 3）。
  testWidgets('手工编辑后剩余卡变 stale', (t) async {
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'));
    final adapter = FakeBackendAdapter();
    adapter.register(
      'POST',
      '/api/v1/preparation-plans/pp_1/assistant',
      (options) async => ResponseBody.fromString(
        jsonEncode({
          'code': 0,
          'message': 'ok',
          'data': {
            'reply': '我整理了两项可单独确认的调整。',
            'change_set': {
              'id': 'cs_two_pending',
              'base_plan_revision': 1,
              'cards': [
                {
                  'id': 'cc_add_a',
                  'type': 'add_task',
                  'target_phase_key': 'defense_prep',
                  'new_task': {
                    'title': '第一次模拟答辩',
                    'estimated_hours': 3,
                    'due_date': '2026-06-05',
                    'note': '记录评委追问',
                  },
                  'summary': '答辩准备阶段新增一次模拟答辩',
                  'rationale': '在正式答辩前预留复盘时间。',
                  'status': 'pending',
                },
                {
                  'id': 'cc_add_b',
                  'type': 'add_task',
                  'target_phase_key': 'defense_prep',
                  'new_task': {
                    'title': '第二次模拟答辩',
                    'estimated_hours': 3,
                    'due_date': '2026-06-08',
                    'note': '复盘改进',
                  },
                  'summary': '答辩准备阶段再增一次模拟答辩',
                  'rationale': '巩固表达。',
                  'status': 'pending',
                },
              ],
            },
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);
    // 预置计划 revision=1（与 base_plan_revision 对齐）。
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(id: 'pp_1', revision: 0));

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '加两次模拟答辩');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // 两张 pending 卡均可接受。
    expect(find.text('接受'), findsNWidgets(2));

    // 手工改计划：save 触发 revision 1→2（expectedRevision 仍 1）。
    await container
        .read(preparationPlanRepositoryProvider)
        .save(
          _plan(id: 'pp_1', revision: 1).copyWith(personalizedSummary: '手动备注'),
        );

    await t.tap(find.text('接受').first);
    await t.pumpAndSettle();

    // 被点的卡标 stale；接受按钮全部消失（两张 pending 卡均被 cascade 标 stale）。
    expect(find.text('已过期'), findsWidgets);
    expect(find.textContaining('计划已变化'), findsWidgets);
    expect(find.text('接受'), findsNothing);
    // cascade：两张 pending 卡均落盘为 stale，无残留 pending。
    final store = container.read(assistantHistoryStoreProvider);
    final persisted = await store.list('pp_1');
    final statuses = persisted.last.cardStatuses;
    expect(statuses['cc_add_a'], ChangeCardStatus.stale);
    expect(statuses['cc_add_b'], ChangeCardStatus.stale);
    expect(statuses.values, isNot(contains(ChangeCardStatus.pending)));
  });

  /// 拒绝后卡标 declined + 折叠（被拒卡的 rationale 隐藏）。
  testWidgets('拒绝后卡标 declined 折叠', (t) async {
    final container = await _bootstrap(savePlan: true);
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '往后挪');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    await t.tap(find.text('拒绝').first);
    await t.pumpAndSettle();

    expect(find.text('已忽略'), findsOneWidget);
    // 撤销入口存在。
    expect(find.textContaining('撤销'), findsOneWidget);
    // 被拒卡落盘为 declined。
    final store = container.read(assistantHistoryStoreProvider);
    final persisted = await store.list('pp_1');
    expect(
      persisted.last.cardStatuses.values,
      contains(ChangeCardStatus.declined),
    );
  });

  /// 保存失败（真实 CAS 竞争 ConflictException）卡保持 pending + 显示错误。
  ///
  /// 用忠实 CAS 仓库：drawer findById 读到 revision=1（匹配 expectedRevision），
  /// 但 save 时模拟另一写入者抢先 bump revision → 抛 ConflictException。
  testWidgets('保存失败卡保持 pending', (t) async {
    final plan = _plan();
    final fakeRepo = _ConflictRepo(plan);
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'))
      ..httpClientAdapter = FakeBackendAdapter();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
        preparationPlanRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '往后挪');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // 模拟 findById 与 save 之间并发写入：save 内 CAS 校验失败。
    fakeRepo.raceNextSave();
    await t.tap(find.text('接受').first);
    await t.pumpAndSettle();

    // 卡仍 pending（待确认），接受按钮仍可点，错误文案可见。
    expect(find.text('待确认'), findsWidgets);
    expect(find.textContaining('数据已变化'), findsOneWidget);
    // 仓库未被本次 accept 落盘（CAS 失败）。
    expect(fakeRepo.saveCount, 0);
  });

  /// 已 applied 的卡再点接受幂等（不重复写计划、revision 不再变）。
  ///
  /// 用计数仓库：第一次接受 saveCount=1、revision 1→2、新增一个任务；
  /// 再次直接调用同一卡的 onAccept 回调（绕过已消失的接受按钮）→ 命中
  /// `if (current == applied) return` 守卫，不二次落盘、不重复新增任务。
  testWidgets('已应用卡再点接受幂等', (t) async {
    final plan = _plan();
    final fakeRepo = _ConflictRepo(plan);
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'))
      ..httpClientAdapter = FakeBackendAdapter();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
        preparationPlanRepositoryProvider.overrideWithValue(fakeRepo),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '往后挪');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();

    // 第一次接受：唯一可接受的 addTask 卡（cc_fake_add）落盘一次，revision 1→2，
    // defense_prep 新增「第二次模拟答辩」任务。
    await t.tap(find.text('接受').first);
    await t.pumpAndSettle();
    expect(fakeRepo.saveCount, 1);
    expect(fakeRepo.findById('pp_1')!.revision, 2);
    final defenseAfterFirst = fakeRepo
        .findById('pp_1')!
        .phases
        .firstWhere((p) => p.key == 'defense_prep');
    final taskCountAfterFirst = defenseAfterFirst.tasks.length;
    expect(defenseAfterFirst.tasks.any((tk) => tk.title == '第二次模拟答辩'), isTrue);

    // 接受按钮已被「已应用」替换；直接重新调用该 applied 卡的 onAccept 回调，
    // 模拟重复点击——应命中 `if (current == applied) return` 守卫，不二次落盘、
    // 不重复新增任务、revision 不再变。
    final appliedCardFinder = find.byWidgetPredicate(
      (w) => w is PlanChangeCardView && w.status == ChangeCardStatus.applied,
    );
    expect(appliedCardFinder, findsOneWidget);
    final cardView = t.widget<PlanChangeCardView>(appliedCardFinder);
    expect(cardView.onAccept, isNotNull);
    cardView.onAccept!();
    await t.pumpAndSettle();

    expect(fakeRepo.saveCount, 1);
    expect(fakeRepo.findById('pp_1')!.revision, 2);
    final defenseAfterSecond = fakeRepo
        .findById('pp_1')!
        .phases
        .firstWhere((p) => p.key == 'defense_prep');
    expect(defenseAfterSecond.tasks.length, taskCountAfterFirst);
  });

  testWidgets('关闭抽屉后请求完成，重开可见该轮回复', (t) async {
    final container = await _bootstrap();
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '关抽屉测试');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    // 不等完成——模拟用户立刻关抽屉。
    await t.pump(const Duration(milliseconds: 10));

    // 重新挂载（模拟重开）：controller 非 autoDispose，state 存活。
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    expect(find.textContaining('我整理了两项可单独确认的调整'), findsOneWidget);
    expect(find.textContaining('关抽屉测试'), findsOneWidget);
  });

  testWidgets('清理上下文清空历史但计划仍在', (t) async {
    final container = await _bootstrap(savePlan: true);
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '第一轮');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pumpAndSettle();
    expect(find.textContaining('第一轮'), findsOneWidget);

    // 点清理上下文图标。
    await t.tap(find.byIcon(Icons.cleaning_services_outlined));
    await t.pumpAndSettle();
    // 二次确认。
    await t.tap(find.text('清理'));
    await t.pumpAndSettle();

    // 历史清空。
    expect(find.textContaining('第一轮'), findsNothing);
    expect(find.textContaining('我整理了两项可单独确认的调整'), findsNothing);
    // 计划仍在。
    expect(
      container.read(preparationPlanRepositoryProvider).findById('pp_1'),
      isNotNull,
    );
    // store 清空。
    final persisted = await container
        .read(assistantHistoryStoreProvider)
        .list('pp_1');
    expect(persisted, isEmpty);
  });

  testWidgets('发送中清理上下文按钮禁用', (t) async {
    // 用 Completer 挂住 send，让 sending 状态可被观测（同步 fake 后端会
    // 在单个 microtask 内 resolve，pump(10ms) 无法捕捉 sending=true）。
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'))
      ..httpClientAdapter = FakeBackendAdapter();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);
    addTearDown(() {
      if (!completer.isCompleted) {
        completer.complete(
          const AssistantReply(
            reply: '',
            changeSet: PlanChangeSet(id: 'cs', basePlanRevision: 1, cards: []),
            requestId: '',
          ),
        );
      }
    });
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(id: 'pp_1', revision: 0));

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '发送中');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pump(); // 让 send 同步前缀（sending=true）生效并重建一帧。

    // sending 中：清理上下文按钮禁用（onPressed == null）。
    final clearBtn = t.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.cleaning_services_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(clearBtn.onPressed, isNull);
    expect(
      container.read(preparationAssistantControllerProvider('pp_1')).sending,
      isTrue,
    );
  });

  testWidgets('发送瞬间用户消息乐观显示（AI 回复到达前）', (t) async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://fake.local'))
      ..httpClientAdapter = FakeBackendAdapter();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          AppConfig(
            dataSource: DataSource.http,
            api: const ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        dioProvider.overrideWithValue(dio),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(dio.close);
    addTearDown(() {
      if (!completer.isCompleted) {
        completer.complete(
          const AssistantReply(
            reply: '',
            changeSet: PlanChangeSet(id: 'cs', basePlanRevision: 1, cards: []),
            requestId: '',
          ),
        );
      }
    });
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(id: 'pp_1', revision: 0));

    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), '乐观显示这条');
    await t.pump();
    await t.tap(find.byIcon(Icons.arrow_upward));
    await t.pump(); // 让 send 同步前缀生效：pendingUserMessage 已置位。

    // AI 尚未回复（completer 未 complete）：用户消息已立即出现。
    expect(find.textContaining('乐观显示这条'), findsOneWidget);
    // AI 固定回复尚未出现。
    expect(find.textContaining('我整理了两项可单独确认的调整'), findsNothing);
  });

  testWidgets('header 显示「竞航小助手」标题', (t) async {
    final container = await _bootstrap();
    await t.pumpWidget(_harness(container));
    await t.pumpAndSettle();

    expect(find.text('竞航小助手'), findsOneWidget);
  });
}

/// 模拟真实仓库 CAS 语义的仓库（与 [LocalPreparationPlanRepository.save]
/// 对齐）：内存维护一份计划；save 时若 `existing.revision != plan.revision`
/// 抛 [ConflictException]，否则落盘 `plan.copyWith(revision: plan.revision+1)`
/// 并返回。`saveCount` 供幂等测试断言 save 调用次数。
class _ConflictRepo implements PreparationPlanRepository {
  _ConflictRepo(PreparationPlan plan) : _plan = plan;

  PreparationPlan _plan;
  int saveCount = 0;

  /// 一次性标志：下一次 save 时在 CAS 校验前并发改写内存计划 revision，
  /// 使 drawer 的 findById（已读到匹配 revision）与 save 之间发生真实竞争，
  /// 从而触发 [ConflictException] 分支（而非 stale-cascade 分支）。
  bool _raceNextSave = false;

  @override
  PreparationPlan? findById(String id) => id == _plan.id ? _plan : null;

  @override
  List<PreparationPlan> list() => [_plan];

  @override
  PreparationPlan? activeForCompetition(String competitionId) => _plan;

  @override
  Stream<List<PreparationPlan>> watch() async* {
    yield [_plan];
  }

  /// 标记下一次 save 触发并发竞争：模拟 findById 与 save 之间另一写入者
  /// 抢先 bump 了 revision。
  void raceNextSave() => _raceNextSave = true;

  @override
  Future<PreparationPlan> save(PreparationPlan plan) async {
    if (_raceNextSave) {
      _raceNextSave = false;
      _plan = _plan.copyWith(revision: _plan.revision + 1);
    }
    final existing = _plan;
    if (existing.revision != plan.revision) {
      throw const ConflictException();
    }
    final updated = plan.copyWith(revision: plan.revision + 1);
    _plan = updated;
    saveCount++;
    return updated;
  }

  /// 模拟并发写入：外部直接覆盖内存计划（用于 stale / conflict 测试）。
  void simulateConcurrentWrite(PreparationPlan plan) => _plan = plan;

  @override
  Future<void> archive(String id) async {}

  @override
  Future<void> delete(String id) async {}
}

/// 可控的助手 fake：通过 [Completer] 挂住 `suggestChanges`，使 `sending`
/// 状态可被 widget 测试观测（同步 fake 后端会在单 microtask 内 resolve，
/// 无法用 `pump(10ms)` 捕捉 sending=true）。与 controller 单测中同名类对齐。
class _ControllableAssistant implements PreparationPlanAssistant {
  _ControllableAssistant(this.completer);

  final Completer<AssistantReply> completer;

  @override
  Future<Result<AssistantReply>> suggestChanges(
    PlanAssistantRequest request,
  ) async {
    try {
      final reply = await completer.future;
      return Success(reply);
    } catch (_) {
      return Failure(ServerException());
    }
  }
}
