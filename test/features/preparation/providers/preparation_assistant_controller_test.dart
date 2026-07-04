import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/assistant_turn.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_assistant.dart';
import 'package:scho_navi/features/preparation/providers/preparation_providers.dart';

class _ControllableAssistant implements PreparationPlanAssistant {
  _ControllableAssistant(this.completer);
  final Completer<AssistantReply> completer;
  int callCount = 0;
  PlanAssistantRequest? lastRequest;

  @override
  Future<Result<AssistantReply>> suggestChanges(
    PlanAssistantRequest request,
  ) async {
    callCount++;
    lastRequest = request;
    try {
      final reply = await completer.future;
      return Success(reply);
    } catch (e) {
      return Failure(ServerException());
    }
  }
}

PreparationPlan _plan({String id = 'pp_1', int revision = 1}) =>
    PreparationPlan(
      id: id,
      competition: CompetitionSnapshot(
        id: 'comp_demo',
        name: 'Demo',
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
      weeklyCommitment: WeeklyCommitment.hours6to10,
      experienceLevel: ExperienceLevel.intermediate,
      status: PreparationPlanStatus.active,
      phases: const [],
      createdAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
      revision: revision,
    );

Future<ProviderContainer> _container({bool savePlan = false}) async {
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      initialAppConfigProvider.overrideWithValue(
        const AppConfig(
          dataSource: DataSource.llm,
          api: ApiConfig(baseUrl: 'https://fake.local'),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (savePlan) {
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));
  }
  return container;
}

AssistantReply _replyWithAddCard() => AssistantReply(
  reply: '加一次模拟答辩',
  changeSet: PlanChangeSet(
    id: 'cs_1',
    basePlanRevision: 1,
    cards: [
      PlanChangeCard(
        id: 'cc_add',
        type: ChangeCardType.addTask,
        targetPhaseKey: 'defense_prep',
        summary: '答辩准备阶段新增一次模拟答辩',
        rationale: '在正式答辩前预留复盘时间。',
        status: ChangeCardStatus.pending,
        newTask: NewTaskDraft(
          title: '第二次模拟答辩',
          estimatedHours: 3,
          dueDate: DateTime(2026, 6, 5),
        ),
      ),
    ],
  ),
  requestId: 'req_x',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('初始 state 为 empty，load 后注入 currentPlan', () async {
    final container = await _container(savePlan: true);
    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    // 首帧后 microtask load。
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state.turns, isEmpty);
    expect(ctrl.state.sending, isFalse);
    expect(ctrl.state.currentPlan, isNotNull);
    expect(ctrl.state.currentPlan!.id, 'pp_1');
  });

  test('send 成功追加 turn 并落盘', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero); // 让 load 完成

    ctrl.send('往后挪');
    expect(ctrl.state.sending, isTrue);
    completer.complete(
      const AssistantReply(
        reply: '已调整',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 1, cards: []),
        requestId: 'req_x',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero); // 让 append + state 刷新

    expect(ctrl.state.sending, isFalse);
    expect(ctrl.state.turns, hasLength(1));
    expect(ctrl.state.turns.first.reply, '已调整');
    expect(ctrl.state.turns.first.requestId, 'req_x');
    expect(fake.lastRequest!.basePlanRevision, 1);
    // 落盘
    final persisted = await container
        .read(assistantHistoryStoreProvider)
        .list('pp_1');
    expect(persisted, hasLength(1));
    expect(persisted.first.reply, '已调整');
  });

  test('send 用最新计划 revision（发送前改计划）', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    final repo = container.read(preparationPlanRepositoryProvider);
    await repo.save(_plan(revision: 0)); // revision -> 1

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    // 发送前手工改计划：revision 1 -> 2。
    await repo.save(_plan(revision: 1).copyWith(personalizedSummary: '手动'));

    ctrl.send('问');
    completer.complete(
      const AssistantReply(
        reply: '答',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 2, cards: []),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 请求的 basePlanRevision 应是最新 2，而非 load 时的 1。
    expect(fake.lastRequest!.basePlanRevision, 2);
  });

  test('send 回传成功历史的 user/assistant 与 card results，跳过失败轮', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));
    final store = container.read(assistantHistoryStoreProvider);
    await store.append(
      'pp_1',
      AssistantTurn(
        id: 'turn_ok',
        planId: 'pp_1',
        userMessage: '上一轮用户',
        reply: '上一轮回复',
        changeSet: const PlanChangeSet(
          id: 'cs_prev',
          basePlanRevision: 1,
          cards: [],
        ),
        createdAt: DateTime.utc(2026, 5, 1),
        cardStatuses: const {
          'card-1': ChangeCardStatus.applied,
          'card-2': ChangeCardStatus.declined,
        },
      ),
    );
    await store.append(
      'pp_1',
      AssistantTurn(
        id: 'turn_err',
        planId: 'pp_1',
        userMessage: '失败轮用户',
        reply: '助手调用失败，请稍后重试。',
        createdAt: DateTime.utc(2026, 5, 2),
        cardStatuses: const {},
        error: true,
      ),
    );

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    final sendFuture = ctrl.send('新的问题');
    expect(fake.lastRequest, isNotNull);
    final history = fake.lastRequest!.history;
    expect(history, hasLength(2));
    expect(history[0].role, 'user');
    expect(history[0].content, '上一轮用户');
    expect(history[0].cardResults, isEmpty);
    expect(history[1].role, 'assistant');
    expect(history[1].content, '上一轮回复');
    expect(
      history[1].cardResults.map((r) => '${r.cardId}:${r.status}').toList(),
      ['card-1:applied', 'card-2:declined'],
    );
    expect(history.map((h) => h.content), isNot(contains('失败轮用户')));

    completer.complete(
      const AssistantReply(
        reply: '答',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 1, cards: []),
      ),
    );
    await sendFuture;
  });

  test('send 失败 turn 落盘 error:true', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('问');
    completer.completeError(Exception('boom'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ctrl.state.sending, isFalse);
    expect(ctrl.state.turns, hasLength(1));
    expect(ctrl.state.turns.first.error, isTrue);
    final persisted = await container
        .read(assistantHistoryStoreProvider)
        .list('pp_1');
    expect(persisted.first.error, isTrue);
  });

  test('sending 中再次 send 被忽略', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('第一条');
    expect(fake.callCount, 1);
    ctrl.send('第二条'); // sending 中，应忽略
    expect(fake.callCount, 1);
    completer.complete(
      const AssistantReply(
        reply: '答',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 1, cards: []),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state.turns, hasLength(1));
  });

  test('clearContext 清空 turns 但不删计划', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('问');
    completer.complete(_replyWithAddCard());
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state.turns, hasLength(1));

    await ctrl.clearContext();
    expect(ctrl.state.turns, isEmpty);
    expect(ctrl.state.cardStatuses, isEmpty);
    expect(ctrl.state.currentPlan, isNotNull); // 计划仍在
    final persisted = await container
        .read(assistantHistoryStoreProvider)
        .list('pp_1');
    expect(persisted, isEmpty);
    expect(
      container.read(preparationPlanRepositoryProvider).findById('pp_1'),
      isNotNull,
    );
  });

  test('sending 中 clearContext 被忽略', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('问'); // sending
    await ctrl.clearContext(); // 应被忽略
    expect(ctrl.state.sending, isTrue);
    completer.complete(
      const AssistantReply(
        reply: '答',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 1, cards: []),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(ctrl.state.turns, hasLength(1)); // send 仍完成
  });

  test('send 瞬间 pendingUserMessage 立即置位（乐观显示）', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('往后挪一周');
    // 尚未 complete：sending=true，pendingUserMessage 已置位，turns 未追加。
    expect(ctrl.state.sending, isTrue);
    expect(ctrl.state.pendingUserMessage, '往后挪一周');
    expect(ctrl.state.turns, isEmpty);

    completer.complete(
      const AssistantReply(
        reply: '已调整',
        changeSet: PlanChangeSet(id: 'cs_1', basePlanRevision: 1, cards: []),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    // 成功后 pendingUserMessage 清空，turns 追加真实 turn。
    expect(ctrl.state.sending, isFalse);
    expect(ctrl.state.pendingUserMessage, isNull);
    expect(ctrl.state.turns, hasLength(1));
    expect(ctrl.state.turns.first.userMessage, '往后挪一周');
  });

  test('send 失败后 pendingUserMessage 清空并追加 error turn', () async {
    final completer = Completer<AssistantReply>();
    final fake = _ControllableAssistant(completer);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialAppConfigProvider.overrideWithValue(
          const AppConfig(
            dataSource: DataSource.llm,
            api: ApiConfig(baseUrl: 'https://fake.local'),
          ),
        ),
        preparationPlanAssistantProvider.overrideWithValue(fake),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(preparationPlanRepositoryProvider)
        .save(_plan(revision: 0));

    final ctrl = container.read(
      preparationAssistantControllerProvider('pp_1').notifier,
    );
    await Future<void>.delayed(Duration.zero);

    ctrl.send('问');
    expect(ctrl.state.pendingUserMessage, '问');

    completer.completeError(Exception('boom'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(ctrl.state.sending, isFalse);
    expect(ctrl.state.pendingUserMessage, isNull);
    expect(ctrl.state.turns, hasLength(1));
    expect(ctrl.state.turns.first.error, isTrue);
    expect(ctrl.state.turns.first.userMessage, '问');
  });
}
