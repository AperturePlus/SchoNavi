import '../../core/storage/local_store.dart';
import '../../domain/entities/assistant_turn.dart';
import '../../domain/entities/plan_change_card.dart';

/// 备赛助手对话历史本地存储：按 planId 分组保留每计划最近 20 轮对话。
///
/// 持久化于 SharedPreferences key `preparation_assistant_history.v1`，结构为
/// `Map<planId, List<AssistantTurn toJson>>`，每计划内按时间顺序排列。
/// 损坏数据降级返回空，不抛出。
class AssistantHistoryStore {
  AssistantHistoryStore(this._store);

  final LocalStore _store;

  static const _key = 'preparation_assistant_history.v1';

  static const int _maxTurnsPerPlan = 20;

  Map<String, dynamic> _readAll() {
    final raw = _store.getJson(_key);
    if (raw == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _writeAll(Map<String, dynamic> map) async {
    await _store.setJson(_key, map);
  }

  Future<List<AssistantTurn>> list(String planId) async {
    final all = _readAll();
    return _parseList(all[planId]);
  }

  Future<void> append(String planId, AssistantTurn turn) async {
    final all = _readAll();
    final existing = _parseList(all[planId]);
    existing.add(turn);
    if (existing.length > _maxTurnsPerPlan) {
      existing.removeRange(0, existing.length - _maxTurnsPerPlan);
    }
    all[planId] = existing.map((t) => t.toJson()).toList();
    await _writeAll(all);
  }

  Future<void> clear(String planId) async {
    final all = _readAll();
    if (all.remove(planId) == null) return;
    await _writeAll(all);
  }

  Future<void> clearAll() => _store.remove(_key);

  /// 更新指定 turn 的卡片最终状态（spec §3.6：每轮保存每张卡的最终状态）。
  /// 找不到 planId/turnId 时静默忽略——状态以内存为准，落盘为最佳努力。
  Future<void> updateCardStatuses(
    String planId,
    String turnId,
    Map<String, ChangeCardStatus> cardStatuses,
  ) async {
    final all = _readAll();
    final existing = _parseList(all[planId]);
    final idx = existing.indexWhere((t) => t.id == turnId);
    if (idx < 0) return;
    existing[idx] = AssistantTurn(
      id: existing[idx].id,
      planId: existing[idx].planId,
      userMessage: existing[idx].userMessage,
      reply: existing[idx].reply,
      changeSet: existing[idx].changeSet,
      createdAt: existing[idx].createdAt,
      error: existing[idx].error,
      cardStatuses: Map<String, ChangeCardStatus>.of(cardStatuses),
      requestId: existing[idx].requestId,
    );
    all[planId] = existing.map((t) => t.toJson()).toList();
    await _writeAll(all);
  }

  Future<Map<String, List<AssistantTurn>>> all() async {
    final raw = _readAll();
    final result = <String, List<AssistantTurn>>{};
    raw.forEach((k, v) {
      final parsed = _parseList(v);
      if (parsed.isEmpty) return;
      result[k] = parsed;
    });
    return result;
  }

  List<AssistantTurn> _parseList(Object? raw) {
    if (raw is! List) return <AssistantTurn>[];
    final out = <AssistantTurn>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      try {
        out.add(AssistantTurn.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // 跳过损坏条目，降级返回可解析部分
      }
    }
    return out;
  }
}
