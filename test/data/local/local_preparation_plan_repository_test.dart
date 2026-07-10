import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/storage/shared_preferences_local_store.dart';
import 'package:scho_navi/data/local/local_preparation_plan_repository.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

PreparationPlan _plan({
  required String id,
  required String compId,
  PreparationPlanStatus status = PreparationPlanStatus.active,
}) => PreparationPlan(
  id: id,
  competition: CompetitionSnapshot(
    id: compId,
    name: 'C',
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
  status: status,
  phases: const [],
  createdAt: DateTime(2026, 6, 28),
  updatedAt: DateTime(2026, 6, 28),
);

Future<SharedPreferencesLocalStore> _storeWith(Map<String, Object> prefs) {
  // SharedPreferencesLocalStore.setJsonList stores lists as jsonEncode(...)'d
  // String; mock initial values must match that shape so getJsonList decodes.
  final encoded = prefs.map(
    (k, v) => MapEntry(k, v is List ? jsonEncode(v) : v),
  );
  SharedPreferences.setMockInitialValues(encoded);
  return SharedPreferences.getInstance().then(
    (p) => SharedPreferencesLocalStore(p),
  );
}

Map<String, dynamic> _legacyPlanJson() => {
  'id': 'pp_legacy',
  'competition': {
    'id': 'c1',
    'name': '赛',
    'category': '计算机类',
    'rules_summary': {
      'signup_time': '1',
      'contest_time': '2',
      'team_size': '3',
      'format': '现场',
      'organizer': 'o',
    },
  },
  'target_date': '2026-06-01T00:00:00.000',
  'weekly_commitment': 'hours6to10',
  'experience_level': 'intermediate',
  'status': 'active',
  'phases': <dynamic>[],
  'created_at': '2026-05-01T00:00:00.000Z',
  'updated_at': '2026-05-01T00:00:00.000Z',
  'tight_schedule': false,
  'overload': false,
};

Map<String, dynamic> _v2PlanJson() => {
  'id': 'pp_v2',
  'competition': {
    'id': 'c1',
    'name': '赛',
    'category': '计算机类',
    'rules_summary': {
      'signup_time': '1',
      'contest_time': '2',
      'team_size': '3',
      'format': '现场',
      'organizer': 'o',
    },
  },
  'target_date': '2026-06-01',
  'weekly_commitment': 'hours6to10',
  'experience_level': 'intermediate',
  'status': 'active',
  'phases': <dynamic>[],
  'created_at': '2026-05-01T00:00:00.000Z',
  'updated_at': '2026-05-01T00:00:00.000Z',
  'tight_schedule': false,
  'overload': false,
  'timeline_type': 'submission',
  'revision': 2,
};

void main() {
  late LocalPreparationPlanRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalPreparationPlanRepository(
      SharedPreferencesLocalStore(await SharedPreferences.getInstance()),
    );
  });

  test('save 后 list/watch 可见', () async {
    await repo.save(_plan(id: 'p1', compId: 'c1'));
    expect(repo.list().length, 1);
    final firstEvt = await repo.watch().first;
    expect(firstEvt.length, 1);
  });

  test('activeForCompetition 返回进行中计划', () async {
    await repo.save(_plan(id: 'p1', compId: 'c1'));
    final a = repo.activeForCompetition('c1');
    expect(a, isNotNull);
    expect(a!.id, 'p1');
    expect(repo.activeForCompetition('c2'), isNull);
  });

  test('归档后 activeForCompetition 为 null', () async {
    await repo.save(_plan(id: 'p1', compId: 'c1'));
    await repo.archive('p1');
    expect(repo.activeForCompetition('c1'), isNull);
    expect(repo.findById('p1')!.status, PreparationPlanStatus.archived);
  });

  test('同一竞赛最多一个 active：save 第二个同竞赛 plan 仍存为独立条目（由生成器/页面保证唯一，仓库不强制）', () async {
    await repo.save(_plan(id: 'p1', compId: 'c1'));
    await repo.save(_plan(id: 'p2', compId: 'c1'));
    expect(repo.list().length, 2);
  });

  test('delete 移除', () async {
    await repo.save(_plan(id: 'p1', compId: 'c1'));
    await repo.delete('p1');
    expect(repo.list(), isEmpty);
  });

  test('损坏数据降级忽略', () async {
    // 直接写坏 JSON 到 store
    final store = SharedPreferencesLocalStore(
      await SharedPreferences.getInstance(),
    );
    await store.setJsonList(LocalPreparationPlanRepository.storageKey, [
      {'id': 'bad', 'competition': null}, // 缺字段
    ]);
    expect(repo.list(), isEmpty);
  });

  group('v2 迁移', () {
    test(
      'v1 存在且 v2 缺失时 list 读到 submission + revision 0，save 后写 v2 并保留 v1',
      () async {
        final store = await _storeWith({
          'competition_preparation_plans.v1': [_legacyPlanJson()],
        });
        final repo = LocalPreparationPlanRepository(
          store,
          now: () => DateTime(2026, 6, 1),
        );
        // 懒迁移：list 只解码 v1，不写 v2。
        final plans = repo.list();
        expect(plans, hasLength(1));
        expect(plans.first.id, 'pp_legacy');
        expect(plans.first.timelineType, CompetitionTimelineType.submission);
        expect(plans.first.revision, 0);
        // 首次 save 后 v2 被写入。
        await repo.save(plans.first);
        expect(
          store.getJsonList('competition_preparation_plans.v2'),
          isNotNull,
        );
        // v1 保留（不删，便于回滚）。
        expect(
          store.getJsonList('competition_preparation_plans.v1'),
          isNotNull,
        );
      },
    );

    test('v2 已存在时不走 v1 迁移路径', () async {
      final store = await _storeWith({
        'competition_preparation_plans.v1': [_legacyPlanJson()],
        'competition_preparation_plans.v2': [_v2PlanJson()],
      });
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      final plans = repo.list();
      expect(plans.first.id, 'pp_v2');
      expect(plans.first.revision, 2);
    });

    test('v1 单条损坏降级，保留其他合法', () async {
      final store = await _storeWith({
        'competition_preparation_plans.v1': [
          {'broken': 'not a plan'},
          _legacyPlanJson(),
        ],
      });
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      final plans = repo.list();
      expect(plans, hasLength(1));
      expect(plans.first.id, 'pp_legacy');
    });
  });

  group('compare-and-set 写队列', () {
    test('新计划要求 revision==0', () async {
      final store = await _storeWith({});
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      final plan = _plan(id: 'p1', compId: 'c1').copyWith(revision: 3);
      await expectLater(repo.save(plan), throwsA(isA<ConflictException>()));
      expect(repo.list(), isEmpty);
    });

    test('已存在计划 revision 不匹配抛 ConflictException', () async {
      final store = await _storeWith({});
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      final saved = await repo.save(_plan(id: 'p1', compId: 'c1'));
      expect(saved.revision, 1);
      // 用过期 revision 再次保存应冲突。
      final stale = _plan(id: 'p1', compId: 'c1').copyWith(revision: 0);
      await expectLater(repo.save(stale), throwsA(isA<ConflictException>()));
    });

    test('save 成功后 revision+1 且 updatedAt 刷新', () async {
      final store = await _storeWith({});
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      final saved = await repo.save(_plan(id: 'p1', compId: 'c1'));
      expect(saved.revision, 1);
      expect(saved.updatedAt, DateTime(2026, 6, 1));
      final again = await repo.save(saved);
      expect(again.revision, 2);
    });

    test('并发 save 串行化不丢更新', () async {
      final store = await _storeWith({});
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      // 三个不同 id 的 save 并发触发，写队列应串行全部落盘。
      await Future.wait([
        repo.save(_plan(id: 'a', compId: 'c1')),
        repo.save(_plan(id: 'b', compId: 'c2')),
        repo.save(_plan(id: 'c', compId: 'c3')),
      ]);
      expect(repo.list().map((p) => p.id).toSet(), {'a', 'b', 'c'});
    });
  });

  group('clearAll', () {
    test('删除 v2 与 v1 遗留数据并向 watch 发出空列表', () async {
      final store = await _storeWith({
        'competition_preparation_plans.v1': [_legacyPlanJson()],
        'competition_preparation_plans.v2': [_v2PlanJson()],
      });
      final repo = LocalPreparationPlanRepository(
        store,
        now: () => DateTime(2026, 6, 1),
      );
      expect(repo.list(), isNotEmpty);

      final events = <List<PreparationPlan>>[];
      final subscription = repo.watch().listen(events.add);
      addTearDown(subscription.cancel);

      await repo.clearAll();
      await Future<void>.delayed(Duration.zero);

      expect(repo.list(), isEmpty);
      expect(
        store.getJsonList(LocalPreparationPlanRepository.storageKey),
        isNull,
      );
      expect(store.getJsonList('competition_preparation_plans.v1'), isNull);
      expect(events, isNotEmpty);
      expect(events.last, isEmpty);
    });
  });
}
