import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/storage/local_store.dart';
import 'package:scho_navi/core/storage/shared_preferences_local_store.dart';
import 'package:scho_navi/data/local/level_diagnosis_store.dart';
import 'package:scho_navi/domain/entities/level_diagnosis.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
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

LevelDiagnosis _diag({
  String categoryKey = '计算机类',
  ExperienceLevel diagnosed = ExperienceLevel.intermediate,
  ExperienceLevel effective = ExperienceLevel.intermediate,
  DiagnosisSelectionSource source = DiagnosisSelectionSource.aiAccepted,
  String rationale = 'AI 判断',
  String? suggestion,
  Map<String, String> answers = const {},
  DateTime? diagnosedAt,
}) => LevelDiagnosis(
  categoryKey: categoryKey,
  diagnosedLevel: diagnosed,
  effectiveLevel: effective,
  source: source,
  rationale: rationale,
  suggestion: suggestion,
  diagnosedAt: diagnosedAt ?? DateTime(2026, 6, 1),
  answers: answers,
);

void main() {
  test('save/get 按 categoryKey 存取并往返保持所有字段', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    final original = _diag(
      diagnosed: ExperienceLevel.beginner,
      effective: ExperienceLevel.experienced,
      source: DiagnosisSelectionSource.manualOverride,
      rationale: '理由',
      suggestion: '建议',
      answers: {'q1': 'a1', 'q2': 'a2'},
      diagnosedAt: DateTime.utc(2026, 6, 1, 12, 30),
    );
    await store.save(original);

    final loaded = await store.get('计算机类');
    expect(loaded, isNotNull);
    expect(loaded!.categoryKey, '计算机类');
    expect(loaded.diagnosedLevel, ExperienceLevel.beginner);
    expect(loaded.effectiveLevel, ExperienceLevel.experienced);
    expect(loaded.source, DiagnosisSelectionSource.manualOverride);
    expect(loaded.rationale, '理由');
    expect(loaded.suggestion, '建议');
    expect(loaded.diagnosedAt, DateTime.utc(2026, 6, 1, 12, 30));
    expect(loaded.answers, {'q1': 'a1', 'q2': 'a2'});
  });

  test('save 覆盖同一 categoryKey 的旧诊断', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag(effective: ExperienceLevel.beginner));
    await store.save(_diag(effective: ExperienceLevel.experienced));

    expect(
      (await store.get('计算机类'))?.effectiveLevel,
      ExperienceLevel.experienced,
    );
  });

  test('save 多个 categoryKey 互不影响', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag(categoryKey: '计算机类'));
    await store.save(
      _diag(categoryKey: '数学类', effective: ExperienceLevel.beginner),
    );

    expect(
      (await store.get('计算机类'))?.effectiveLevel,
      ExperienceLevel.intermediate,
    );
    expect((await store.get('数学类'))?.effectiveLevel, ExperienceLevel.beginner);
  });

  test('get 未存储的 categoryKey 返回 null', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    expect(await store.get('未知'), isNull);
  });

  test('clear 移除指定 categoryKey', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag(categoryKey: '计算机类'));
    await store.save(_diag(categoryKey: '数学类'));

    await store.clear('计算机类');
    expect(await store.get('计算机类'), isNull);
    expect(await store.get('数学类'), isNotNull);
  });

  test('clear 未存储的 categoryKey 不抛出且不改变其他项', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag());
    await store.clear('不存在');
    expect(await store.get('计算机类'), isNotNull);
  });

  test('clearAll 移除全部 categoryKey 的诊断', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag(categoryKey: '计算机类'));
    await store.save(_diag(categoryKey: '数学类'));

    await store.clearAll();
    expect(await store.get('计算机类'), isNull);
    expect(await store.get('数学类'), isNull);
    expect(await store.all(), isEmpty);
  });

  test('all 返回所有诊断', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    await store.save(_diag(categoryKey: '计算机类'));
    await store.save(_diag(categoryKey: '数学类'));

    final all = await store.all();
    expect(all.length, 2);
    expect(all.keys.toSet(), {'计算机类', '数学类'});
  });

  test('all 空存储返回空 map', () async {
    final store = LevelDiagnosisStore(_MemLocalStore());
    expect(await store.all(), isEmpty);
  });

  test('损坏数据：get 返回 null', () async {
    SharedPreferences.setMockInitialValues({'level_diagnosis.v1': 'not-json{'});
    final prefs = await SharedPreferences.getInstance();
    final store = LevelDiagnosisStore(SharedPreferencesLocalStore(prefs));
    expect(await store.get('计算机类'), isNull);
  });

  test('损坏数据：all 返回空 map 不抛出', () async {
    SharedPreferences.setMockInitialValues({'level_diagnosis.v1': 'not-json{'});
    final prefs = await SharedPreferences.getInstance();
    final store = LevelDiagnosisStore(SharedPreferencesLocalStore(prefs));
    expect(await store.all(), isEmpty);
  });

  test('损坏条目：单条 diagnosis 解析失败时 all 跳过该项', () async {
    SharedPreferences.setMockInitialValues({
      'level_diagnosis.v1':
          '{"计算机类": {"categoryKey": 123}, "数学类": '
          '{"categoryKey":"数学类","diagnosedLevel":"beginner",'
          '"effectiveLevel":"beginner","source":"aiAccepted",'
          '"rationale":"r","diagnosedAt":"2026-06-01T00:00:00.000",'
          '"answers":{}}}',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = LevelDiagnosisStore(SharedPreferencesLocalStore(prefs));
    final all = await store.all();
    expect(all.length, 1);
    expect(all.containsKey('数学类'), isTrue);
  });

  test('实体 toJson/fromJson 往返保持一致', () {
    final original = _diag(
      suggestion: '建议',
      answers: {'q1': 'a1'},
      diagnosedAt: DateTime.utc(2026, 6, 1, 8),
    );
    final restored = LevelDiagnosis.fromJson(original.toJson());
    expect(restored, isNotNull);
    expect(restored!.toJson(), original.toJson());
  });
}
