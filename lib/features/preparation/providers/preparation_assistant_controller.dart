import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calendar_date.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/result/result.dart';
import '../../../domain/entities/assistant_turn.dart';
import '../../../domain/entities/plan_change_card.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../../domain/repositories/preparation_plan_assistant.dart';
import '../../../domain/repositories/preparation_plan_repository.dart';
import '../../../domain/services/plan_change_applier.dart';
import '../../../data/local/assistant_history_store.dart';
import 'preparation_providers.dart';

/// 备赛助手抽屉的会话状态（spec §4.1）。不可变；由
/// [PreparationAssistantController] 维护。`sending` 仅内存，不落盘。
@immutable
class PreparationAssistantControllerState {
  const PreparationAssistantControllerState({
    required this.currentPlan,
    required this.turns,
    required this.sending,
    required this.expectedRevisions,
    required this.cardStatuses,
    required this.applying,
    required this.cardErrors,
    this.pendingUserMessage,
    this.lastError,
  });

  final PreparationPlan? currentPlan;
  final List<AssistantTurn> turns;
  final bool sending;
  final Map<String, int> expectedRevisions;
  final Map<String, Map<String, ChangeCardStatus>> cardStatuses;
  final Set<String> applying;
  final Map<String, String> cardErrors;
  final String? pendingUserMessage;
  final AppException? lastError;

  static const empty = PreparationAssistantControllerState(
    currentPlan: null,
    turns: [],
    sending: false,
    expectedRevisions: {},
    cardStatuses: {},
    applying: {},
    cardErrors: {},
    pendingUserMessage: null,
    lastError: null,
  );

  PreparationAssistantControllerState copyWith({
    PreparationPlan? currentPlan,
    List<AssistantTurn>? turns,
    bool? sending,
    Map<String, int>? expectedRevisions,
    Map<String, Map<String, ChangeCardStatus>>? cardStatuses,
    Set<String>? applying,
    Map<String, String>? cardErrors,
    String? pendingUserMessage,
    AppException? lastError,
    bool clearLastError = false,
  }) => PreparationAssistantControllerState(
    currentPlan: currentPlan ?? this.currentPlan,
    turns: turns ?? this.turns,
    sending: sending ?? this.sending,
    expectedRevisions: expectedRevisions ?? this.expectedRevisions,
    cardStatuses: cardStatuses ?? this.cardStatuses,
    applying: applying ?? this.applying,
    cardErrors: cardErrors ?? this.cardErrors,
    pendingUserMessage: pendingUserMessage,
    lastError: clearLastError ? null : lastError ?? this.lastError,
  );
}

/// 备赛助手会话 controller（spec §4）。非 autoDispose——关闭抽屉不销毁 state，
/// 在途请求跨关闭继续执行并落盘。按 planId 家族化（构造注入 planId）。
class PreparationAssistantController
    extends Notifier<PreparationAssistantControllerState> {
  PreparationAssistantController(this.planId);

  final String planId;

  @override
  PreparationAssistantControllerState build() {
    Future.microtask(() => load());
    return PreparationAssistantControllerState.empty;
  }

  PreparationPlanRepository get _repo =>
      ref.read(preparationPlanRepositoryProvider);
  AssistantHistoryStore get _store => ref.read(assistantHistoryStoreProvider);
  PreparationPlanAssistant get _assistant =>
      ref.read(preparationPlanAssistantProvider);

  Future<void> load() async {
    final plan = _repo.findById(planId);
    final turns = await _store.list(planId);
    final expected = <String, int>{};
    final statuses = <String, Map<String, ChangeCardStatus>>{};
    for (final t in turns) {
      if (t.changeSet != null) {
        expected[t.id] ??= t.changeSet!.basePlanRevision;
        statuses[t.id] ??= Map<String, ChangeCardStatus>.from(t.cardStatuses);
      }
    }
    state = state.copyWith(
      currentPlan: plan,
      turns: turns,
      expectedRevisions: expected,
      cardStatuses: statuses,
    );
  }

  /// 发送一轮用户消息（spec §4.2）。关闭抽屉不取消在途请求——state 由非
  /// autoDispose 的本 controller 持有，跨关闭继续 await 并落盘。发送时读取
  /// 仓库最新计划与 revision（非 load 时快照）。`sending` 仅内存不落盘；
  /// 失败 turn 也落盘（`error:true`，无卡），便于重开看到失败轮。
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.sending) return;
    final plan = _repo.findById(planId);
    if (plan == null) return;
    final successfulTurns = state.turns
        .where((t) => !t.error)
        .toList(growable: false);
    final recentTurns = successfulTurns.slice(
      successfulTurns.length > 10 ? successfulTurns.length - 10 : 0,
    );
    final history = recentTurns
        .expand((t) {
          final statuses = state.cardStatuses[t.id] ?? t.cardStatuses;
          return [
            AssistantHistoryEntry(role: 'user', content: t.userMessage),
            AssistantHistoryEntry(
              role: 'assistant',
              content: t.reply,
              cardResults: statuses.entries
                  .map(
                    (entry) => AssistantCardResult(
                      cardId: entry.key,
                      status: encodeChangeCardStatus(entry.value),
                    ),
                  )
                  .toList(growable: false),
            ),
          ];
        })
        .toList(growable: false);
    final requestId = 'req_${DateTime.now().millisecondsSinceEpoch}';
    state = state.copyWith(
      sending: true,
      pendingUserMessage: trimmed,
      clearLastError: true,
    );
    final request = PlanAssistantRequest(
      planId: planId,
      calendarToday: CalendarDate.normalize(DateTime.now()),
      basePlanRevision: plan.revision,
      planSnapshot: plan,
      userMessage: trimmed,
      history: history,
      requestId: requestId,
    );
    final result = await _assistant.suggestChanges(request);
    switch (result) {
      case Success(:final data):
        final turn = AssistantTurn(
          id: 'turn_${DateTime.now().millisecondsSinceEpoch}',
          planId: planId,
          userMessage: trimmed,
          reply: data.reply,
          createdAt: DateTime.now().toUtc(),
          cardStatuses: {for (final c in data.changeSet.cards) c.id: c.status},
          changeSet: data.changeSet,
          requestId: data.requestId.isNotEmpty ? data.requestId : requestId,
        );
        await _store.append(planId, turn);
        final latest = _repo.findById(planId);
        state = state.copyWith(
          currentPlan: latest,
          sending: false,
          turns: [...state.turns, turn],
          expectedRevisions: {
            ...state.expectedRevisions,
            turn.id: data.changeSet.basePlanRevision,
          },
          cardStatuses: {
            ...state.cardStatuses,
            turn.id: {for (final c in data.changeSet.cards) c.id: c.status},
          },
          pendingUserMessage: null,
        );
      case Failure(:final error):
        final turn = AssistantTurn(
          id: 'turn_${DateTime.now().millisecondsSinceEpoch}_err',
          planId: planId,
          userMessage: trimmed,
          reply: '助手调用失败，请稍后重试。',
          createdAt: DateTime.now().toUtc(),
          cardStatuses: const {},
          error: true,
          requestId: requestId,
        );
        await _store.append(planId, turn);
        state = state.copyWith(
          sending: false,
          turns: [...state.turns, turn],
          pendingUserMessage: null,
          lastError: error,
        );
    }
  }

  /// 接受一张改动卡（spec §3.6 步骤 1-8，搬迁自原 drawer，setState→state.copyWith）。
  Future<void> acceptCard(AssistantTurn turn, PlanChangeCard card) async {
    final statuses = state.cardStatuses[turn.id];
    if (statuses == null) return;
    final current = statuses[card.id] ?? card.status;
    // 幂等：已 applied 直接返回。
    if (current == ChangeCardStatus.applied) return;
    // 仅 pending 可接受。
    if (current != ChangeCardStatus.pending) return;
    if (state.applying.contains(card.id)) return;

    state = state.copyWith(
      applying: {...state.applying, card.id},
      cardErrors: {...state.cardErrors}..remove(card.id),
    );

    final latest = _repo.findById(planId);
    if (latest == null) {
      state = state.copyWith(
        applying: state.applying..remove(card.id),
        cardErrors: {...state.cardErrors, card.id: '计划不存在'},
      );
      return;
    }
    final expectedRevision =
        state.expectedRevisions[turn.id] ?? turn.changeSet!.basePlanRevision;

    // Stale 检测：最新计划 revision 与期望不一致 → 本 change set 剩余 pending
    // 全部标 stale（不应用任何卡）。
    if (latest.revision != expectedRevision) {
      final next = Map<String, ChangeCardStatus>.from(statuses);
      _cascadeStale(turn, next);
      state = state.copyWith(
        cardStatuses: {...state.cardStatuses, turn.id: next},
        applying: state.applying..remove(card.id),
      );
      await _persistStatuses(turn, next);
      return;
    }

    final result = PlanChangeApplier.applyCard(
      plan: latest,
      card: card,
      expectedRevision: expectedRevision,
    );

    if (result.stale) {
      final next = Map<String, ChangeCardStatus>.from(statuses);
      _cascadeStale(turn, next);
      state = state.copyWith(
        cardStatuses: {...state.cardStatuses, turn.id: next},
        applying: state.applying..remove(card.id),
      );
      await _persistStatuses(turn, next);
      return;
    }
    if (!result.applied) {
      state = state.copyWith(
        cardErrors: {...state.cardErrors, card.id: result.error ?? '应用失败'},
        applying: state.applying..remove(card.id),
      );
      await _persistStatuses(turn, statuses);
      return;
    }

    // CAS save：newPlan 携当前 revision，仓库校验通过后 revision+1。
    try {
      final saved = await _repo.save(result.newPlan!);
      state = state.copyWith(
        cardStatuses: {
          ...state.cardStatuses,
          turn.id: {...statuses, card.id: ChangeCardStatus.applied},
        },
        expectedRevisions: {
          ...state.expectedRevisions,
          turn.id: saved.revision,
        },
        applying: state.applying..remove(card.id),
        currentPlan: saved,
      );
      await _persistStatuses(turn, state.cardStatuses[turn.id]!);
    } on ConflictException {
      // 卡保持 pending，仅显示错误，不动 UI 计划快照。
      state = state.copyWith(
        cardErrors: {...state.cardErrors, card.id: '数据已变化，请刷新后重试'},
        applying: state.applying..remove(card.id),
      );
    }
  }

  /// 把本 change set 剩余 pending 卡全部标 stale。
  void _cascadeStale(
    AssistantTurn turn,
    Map<String, ChangeCardStatus> statuses,
  ) {
    for (final c in turn.changeSet!.cards) {
      final s = statuses[c.id] ?? c.status;
      if (s == ChangeCardStatus.pending) {
        statuses[c.id] = ChangeCardStatus.stale;
      }
    }
  }

  /// 拒绝一张改动卡：标 declined（折叠），可撤销回 pending。不读计划不应用。
  Future<void> declineCard(AssistantTurn turn, PlanChangeCard card) async {
    final statuses = state.cardStatuses[turn.id];
    if (statuses == null) return;
    final current = statuses[card.id] ?? card.status;
    // declined 可撤销（恢复 pending）；pending 可拒绝。
    if (current != ChangeCardStatus.pending &&
        current != ChangeCardStatus.declined) {
      return;
    }
    final next = Map<String, ChangeCardStatus>.from(statuses);
    next[card.id] = current == ChangeCardStatus.declined
        ? ChangeCardStatus.pending
        : ChangeCardStatus.declined;
    state = state.copyWith(
      cardStatuses: {...state.cardStatuses, turn.id: next},
    );
    await _persistStatuses(turn, next);
  }

  Future<void> _persistStatuses(
    AssistantTurn turn,
    Map<String, ChangeCardStatus> statuses,
  ) async {
    await _store.updateCardStatuses(planId, turn.id, statuses);
  }

  /// 清理上下文（spec §4.4）：清空该计划助手历史并重置内存态，不删计划。
  /// `sending` 时直接返回（发送中禁止清理）。
  Future<void> clearContext() async {
    if (state.sending) return;
    await _store.clear(planId);
    state = state.copyWith(
      turns: const [],
      expectedRevisions: const {},
      cardStatuses: const {},
      applying: const {},
      cardErrors: const {},
      pendingUserMessage: null,
    );
  }
}

extension _ListSlice<T> on List<T> {
  List<T> slice(int start) => start <= 0 ? List<T>.of(this) : sublist(start);
}
