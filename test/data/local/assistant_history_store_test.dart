import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/storage/local_store.dart';
import 'package:scho_navi/core/storage/shared_preferences_local_store.dart';
import 'package:scho_navi/data/local/assistant_history_store.dart';
import 'package:scho_navi/domain/entities/assistant_turn.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemLocalStore implements LocalStore {
  final Map<String, dynamic> _m = {};
  @override
  String? getString(String key) => _m[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _m[key] = value;
  @override
  bool? getBool(String key) => _m[key] as bool?;
  @override
  Future<void> setBool(String key, bool value) async => _m[key] = value;
  @override
  Map<String, dynamic>? getJson(String key) => _m[key] as Map<String, dynamic>?;
  @override
  Future<void> setJson(String key, Map<String, dynamic> value) async =>
      _m[key] = value;
  @override
  List<dynamic>? getJsonList(String key) => _m[key] as List<dynamic>?;
  @override
  Future<void> setJsonList(String key, List<dynamic> value) async =>
      _m[key] = value;
  @override
  bool containsKey(String key) => _m.containsKey(key);
  @override
  Future<void> remove(String key) async => _m.remove(key);
  @override
  Future<void> clear() async => _m.clear();
}

PlanChangeCard _card({
  String id = 'c1',
  ChangeCardType type = ChangeCardType.moveTask,
  ChangeCardStatus status = ChangeCardStatus.pending,
}) => PlanChangeCard(
  id: id,
  type: type,
  targetTaskId: 't1',
  summary: '把任务挪后',
  rationale: '理由',
  status: status,
);

AssistantTurn _turn({
  String id = 'turn1',
  String planId = 'planA',
  String userMessage = '下周太满',
  String reply = '已为你调整',
  PlanChangeSet? changeSet,
  DateTime? createdAt,
  bool error = false,
  Map<String, ChangeCardStatus>? cardStatuses,
  String requestId = '',
}) => AssistantTurn(
  id: id,
  planId: planId,
  userMessage: userMessage,
  reply: reply,
  changeSet: changeSet,
  createdAt: createdAt ?? DateTime.utc(2026, 6, 29, 8),
  error: error,
  cardStatuses: cardStatuses ?? const {},
  requestId: requestId,
);

void main() {
  group('AssistantTurn toJson/fromJson', () {
    test('往返保持所有字段（含 changeSet + cardStatuses）', () {
      final original = _turn(
        changeSet: PlanChangeSet(
          id: 'cs1',
          basePlanRevision: 3,
          cards: [
            _card(id: 'c1', status: ChangeCardStatus.applied),
            _card(id: 'c2', type: ChangeCardType.addTask),
          ],
        ),
        createdAt: DateTime.utc(2026, 6, 29, 12, 30, 45),
        cardStatuses: {
          'c1': ChangeCardStatus.applied,
          'c2': ChangeCardStatus.declined,
        },
      );
      final restored = AssistantTurn.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.planId, original.planId);
      expect(restored.userMessage, original.userMessage);
      expect(restored.reply, original.reply);
      expect(restored.error, original.error);
      expect(restored.createdAt, original.createdAt);
      expect(restored.changeSet, isNotNull);
      expect(restored.changeSet!.id, 'cs1');
      expect(restored.changeSet!.basePlanRevision, 3);
      expect(restored.changeSet!.cards.length, 2);
      expect(restored.changeSet!.cards.first.id, 'c1');
      expect(restored.changeSet!.cards.first.status, ChangeCardStatus.applied);
      expect(restored.cardStatuses, {
        'c1': ChangeCardStatus.applied,
        'c2': ChangeCardStatus.declined,
      });
    });

    test('error turn（changeSet 为 null）往返保持字段', () {
      final original = _turn(
        changeSet: null,
        reply: '调用失败',
        error: true,
        cardStatuses: const {},
      );
      final restored = AssistantTurn.fromJson(original.toJson());
      expect(restored.changeSet, isNull);
      expect(restored.error, isTrue);
      expect(restored.reply, '调用失败');
      expect(restored.cardStatuses, isEmpty);
    });

    test('toJson/fromJson 二次往返稳定', () {
      final original = _turn(
        changeSet: PlanChangeSet(
          id: 'cs1',
          basePlanRevision: 1,
          cards: [_card(id: 'c1')],
        ),
        cardStatuses: {'c1': ChangeCardStatus.applied},
      );
      final once = AssistantTurn.fromJson(original.toJson());
      final twice = AssistantTurn.fromJson(once.toJson());
      expect(twice.toJson(), once.toJson());
    });
  });

  group('AssistantHistoryStore', () {
    test('list 未存储的 planId 返回空列表', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      expect(await store.list('none'), isEmpty);
    });

    test('append/list 按时间顺序保留', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append(
        'planA',
        _turn(id: 't1', createdAt: DateTime.utc(2026, 6, 1)),
      );
      await store.append(
        'planA',
        _turn(id: 't2', createdAt: DateTime.utc(2026, 6, 2)),
      );
      await store.append(
        'planA',
        _turn(id: 't3', createdAt: DateTime.utc(2026, 6, 3)),
      );

      final list = await store.list('planA');
      expect(list.map((t) => t.id), ['t1', 't2', 't3']);
    });

    test('不同 planId 互不影响', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 'a1'));
      await store.append('planB', _turn(id: 'b1'));
      await store.append('planA', _turn(id: 'a2'));

      expect((await store.list('planA')).map((t) => t.id), ['a1', 'a2']);
      expect((await store.list('planB')).map((t) => t.id), ['b1']);
    });

    test('append 超过 20 轮时丢弃最旧（保留最近 20）', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      for (var i = 0; i < 21; i++) {
        await store.append(
          'planA',
          _turn(
            id: 't$i',
            createdAt: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
          ),
        );
      }
      final list = await store.list('planA');
      expect(list.length, 20);
      // 最旧 t0 应被丢弃；保留 t1..t20
      expect(list.first.id, 't1');
      expect(list.last.id, 't20');
    });

    test('append 恰好 20 轮不丢弃', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      for (var i = 0; i < 20; i++) {
        await store.append('planA', _turn(id: 't$i'));
      }
      final list = await store.list('planA');
      expect(list.length, 20);
      expect(list.first.id, 't0');
    });

    test('clear 移除指定 planId 的全部历史', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 'a1'));
      await store.append('planB', _turn(id: 'b1'));

      await store.clear('planA');
      expect(await store.list('planA'), isEmpty);
      expect((await store.list('planB')).map((t) => t.id), ['b1']);
    });

    test('clear 未存储的 planId 不抛出且不影响其他', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 'a1'));
      await store.clear('none');
      expect((await store.list('planA')).map((t) => t.id), ['a1']);
    });

    test('clearAll 移除全部 planId 的历史', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 'a1'));
      await store.append('planB', _turn(id: 'b1'));

      await store.clearAll();
      expect(await store.list('planA'), isEmpty);
      expect(await store.list('planB'), isEmpty);
      expect(await store.all(), isEmpty);
    });

    test('all 返回所有 planId 的历史', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 'a1'));
      await store.append('planB', _turn(id: 'b1'));

      final all = await store.all();
      expect(all.length, 2);
      expect(all.keys.toSet(), {'planA', 'planB'});
      expect(all['planA']!.map((t) => t.id), ['a1']);
    });

    test('all 空存储返回空 map', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      expect(await store.all(), isEmpty);
    });

    test('append 后再读取实体字段完整往返', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      final original = _turn(
        changeSet: PlanChangeSet(
          id: 'cs1',
          basePlanRevision: 2,
          cards: [_card(id: 'c1', status: ChangeCardStatus.applied)],
        ),
        cardStatuses: {'c1': ChangeCardStatus.applied},
      );
      await store.append('planA', original);

      final list = await store.list('planA');
      expect(list.length, 1);
      final restored = list.first;
      expect(restored.changeSet!.id, 'cs1');
      expect(restored.changeSet!.cards.first.status, ChangeCardStatus.applied);
      expect(restored.cardStatuses, {'c1': ChangeCardStatus.applied});
    });

    test('损坏数据（整体非 JSON）：list 返回空不抛出', () async {
      SharedPreferences.setMockInitialValues({
        'preparation_assistant_history.v1': 'not-json{',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AssistantHistoryStore(SharedPreferencesLocalStore(prefs));
      expect(await store.list('planA'), isEmpty);
      expect(await store.all(), isEmpty);
    });

    test('损坏条目（单个 turn 解析失败）：list 跳过该项不抛出', () async {
      SharedPreferences.setMockInitialValues({
        'preparation_assistant_history.v1':
            '{"planA": [{"id": 123}, {"id":"t2","plan_id":"planA",'
            '"user_message":"q","reply":"r","created_at":'
            '"2026-06-29T08:00:00.000Z","error":false,"card_statuses":{}}]}',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AssistantHistoryStore(SharedPreferencesLocalStore(prefs));
      final list = await store.list('planA');
      expect(list.length, 1);
      expect(list.first.id, 't2');
    });

    test('损坏数据下 append 能恢复写入', () async {
      SharedPreferences.setMockInitialValues({
        'preparation_assistant_history.v1': 'not-json{',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = AssistantHistoryStore(SharedPreferencesLocalStore(prefs));
      await store.append('planA', _turn(id: 't1'));
      final list = await store.list('planA');
      expect(list.length, 1);
      expect(list.first.id, 't1');
    });

    test('updateCardStatuses 更新指定 turn 的卡片状态', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append(
        'planA',
        _turn(
          id: 't1',
          changeSet: PlanChangeSet(
            id: 'cs1',
            basePlanRevision: 1,
            cards: [
              _card(id: 'c1'),
              _card(id: 'c2'),
            ],
          ),
          cardStatuses: {
            'c1': ChangeCardStatus.pending,
            'c2': ChangeCardStatus.pending,
          },
        ),
      );

      await store.updateCardStatuses('planA', 't1', {
        'c1': ChangeCardStatus.applied,
        'c2': ChangeCardStatus.declined,
      });

      final list = await store.list('planA');
      expect(list.first.cardStatuses, {
        'c1': ChangeCardStatus.applied,
        'c2': ChangeCardStatus.declined,
      });
    });

    test('updateCardStatuses 保留 turn 的 requestId', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append(
        'planA',
        _turn(
          id: 't1',
          requestId: 'req_keep_me',
          changeSet: PlanChangeSet(
            id: 'cs1',
            basePlanRevision: 1,
            cards: [_card(id: 'c1')],
          ),
          cardStatuses: {'c1': ChangeCardStatus.pending},
        ),
      );

      await store.updateCardStatuses('planA', 't1', {
        'c1': ChangeCardStatus.applied,
      });

      final list = await store.list('planA');
      expect(list.first.cardStatuses, {'c1': ChangeCardStatus.applied});
      expect(list.first.requestId, 'req_keep_me');
    });

    test('updateCardStatuses 未找到 turnId 静默忽略', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 't1'));

      await store.updateCardStatuses('planA', 'nope', {
        'c1': ChangeCardStatus.applied,
      });

      final list = await store.list('planA');
      expect(list.first.cardStatuses, isEmpty);
    });

    test('updateCardStatuses 未找到 planId 静默忽略', () async {
      final store = AssistantHistoryStore(_MemLocalStore());
      await store.append('planA', _turn(id: 't1'));

      await store.updateCardStatuses('planB', 't1', {
        'c1': ChangeCardStatus.applied,
      });

      expect(await store.list('planB'), isEmpty);
    });
  });
}
