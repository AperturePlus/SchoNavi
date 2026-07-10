import 'dart:async';

import '../../core/error/app_exception.dart';
import '../../core/storage/local_store.dart';
import '../../domain/entities/preparation_plan.dart';
import '../../domain/repositories/preparation_plan_repository.dart';

class LocalPreparationPlanRepository implements PreparationPlanRepository {
  LocalPreparationPlanRepository(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const String storageKey = 'competition_preparation_plans.v2';
  static const String _legacyKey = 'competition_preparation_plans.v1';

  final LocalStore _store;
  final DateTime Function() _now;
  final StreamController<List<PreparationPlan>> _controller =
      StreamController<List<PreparationPlan>>.broadcast();
  Future<void> _writeGuard = Future<void>.value();

  @override
  List<PreparationPlan> list() => _readAll();

  @override
  PreparationPlan? findById(String id) {
    for (final plan in list()) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  @override
  PreparationPlan? activeForCompetition(String competitionId) {
    for (final plan in list()) {
      if (plan.status == PreparationPlanStatus.active &&
          plan.competition.id == competitionId) {
        return plan;
      }
    }
    return null;
  }

  @override
  Stream<List<PreparationPlan>> watch() async* {
    yield list();
    yield* _controller.stream;
  }

  @override
  Future<PreparationPlan> save(PreparationPlan plan) => _enqueue(() async {
    final existing = list().where((p) => p.id == plan.id).toList();
    final isNew = existing.isEmpty;
    if (isNew && plan.revision != 0) {
      throw const ConflictException();
    }
    if (!isNew && existing.first.revision != plan.revision) {
      throw const ConflictException();
    }
    final updated = plan.copyWith(
      updatedAt: _now(),
      revision: plan.revision + 1,
    );
    final plans = [
      updated,
      ...list().where((current) => current.id != plan.id),
    ];
    await _writeAll(plans);
    return updated;
  });

  @override
  Future<void> archive(String id) async {
    final plan = findById(id);
    if (plan == null) return;
    await save(plan.copyWith(status: PreparationPlanStatus.archived));
  }

  @override
  Future<void> delete(String id) async {
    await _enqueue(() async {
      final plans = list().where((plan) => plan.id != id).toList();
      await _writeAll(plans);
    });
  }

  @override
  Future<void> clearAll() => _enqueue(() async {
    await _store.remove(storageKey);
    await _store.remove(_legacyKey);
    _controller.add(const <PreparationPlan>[]);
  });

  void dispose() => _controller.close();

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = _writeGuard.then((_) => task());
    _writeGuard = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  List<PreparationPlan> _readAll() {
    // 懒迁移：v2 缺失时直接解码 v1（不写 v2），首次 save/delete 时才落盘 v2。
    final raw =
        _store.getJsonList(storageKey) ?? _store.getJsonList(_legacyKey);
    if (raw == null) return const [];
    final plans = <PreparationPlan>[];
    for (final entry in raw) {
      final plan = _parsePlan(entry);
      if (plan != null) plans.add(plan);
    }
    return plans;
  }

  PreparationPlan? _parsePlan(Object? entry) {
    if (entry is! Map) return null;
    try {
      final json = Map<String, dynamic>.from(entry);
      return PreparationPlan.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeAll(List<PreparationPlan> plans) async {
    await _store.setJsonList(
      storageKey,
      plans.map((plan) => plan.toJson()).toList(growable: false),
    );
    _controller.add(List<PreparationPlan>.unmodifiable(plans));
  }
}
