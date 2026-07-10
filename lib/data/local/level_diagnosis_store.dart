import '../../core/storage/local_store.dart';
import '../../domain/entities/level_diagnosis.dart';

/// 水平诊断画像本地存储：按规范化类目 key 存储一份最新诊断。
///
/// 持久化于 SharedPreferences key `level_diagnosis.v1`，结构为
/// `Map<categoryKey, LevelDiagnosis toJson>`。损坏数据降级返回 null/空，不抛出。
class LevelDiagnosisStore {
  LevelDiagnosisStore(this._store);

  final LocalStore _store;

  static const _key = 'level_diagnosis.v1';

  Map<String, dynamic> _readAll() {
    final raw = _store.getJson(_key);
    if (raw == null) return <String, dynamic>{};
    return Map<String, dynamic>.from(raw);
  }

  Future<void> _writeAll(Map<String, dynamic> map) async {
    await _store.setJson(_key, map);
  }

  Future<LevelDiagnosis?> get(String categoryKey) async {
    final all = _readAll();
    return LevelDiagnosis.fromJson(all[categoryKey]);
  }

  Future<void> save(LevelDiagnosis diagnosis) async {
    final all = _readAll();
    all[diagnosis.categoryKey] = diagnosis.toJson();
    await _writeAll(all);
  }

  Future<void> clear(String categoryKey) async {
    final all = _readAll();
    if (all.remove(categoryKey) == null) return;
    await _writeAll(all);
  }

  Future<void> clearAll() => _store.remove(_key);

  Future<Map<String, LevelDiagnosis>> all() async {
    final raw = _readAll();
    final result = <String, LevelDiagnosis>{};
    raw.forEach((k, v) {
      final d = LevelDiagnosis.fromJson(v);
      if (d != null) result[k] = d;
    });
    return result;
  }
}
