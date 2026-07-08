import 'dart:async';

import '../../core/storage/local_store.dart';
import '../dto/api_envelope.dart';
import '../dto/competition_recommendation_dtos.dart';
import '../../domain/entities/competition_recommendation_result.dart';
import '../../domain/entities/recommendation_result.dart';
import '../../domain/entities/search_history_item.dart';
import '../../domain/repositories/history_repository.dart';

class LocalHistoryRepository implements HistoryRepository {
  LocalHistoryRepository(this._store, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const String storageKey = 'search_history.v1';

  final LocalStore _store;
  final DateTime Function() _now;
  final StreamController<List<SearchHistoryItem>> _controller =
      StreamController<List<SearchHistoryItem>>.broadcast();

  @override
  List<SearchHistoryItem> list() => _readAll();

  @override
  Stream<List<SearchHistoryItem>> watch() async* {
    yield list();
    yield* _controller.stream;
  }

  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async {
    for (final item in list()) {
      if (item.sessionId == sessionId && (type == null || item.type == type)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {
    final item = SearchHistoryItem(
      type: SearchHistoryType.mentor,
      sessionId: result.sessionId,
      prompt: prompt,
      createdAt: _now(),
      summary: _buildSummary(result),
      researchInterests: result.queryUnderstanding.researchInterests,
      preferredLocations: result.queryUnderstanding.preferredLocations,
      recommendationCount: result.recommendations.length,
    );
    final items = [
      item,
      ...list().where((current) => current.sessionId != result.sessionId),
    ]..sort(_byNewest);
    await _writeAll(items);
  }

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {
    final item = SearchHistoryItem(
      type: SearchHistoryType.competition,
      sessionId: result.sessionId,
      prompt: prompt,
      createdAt: _now(),
      summary: _buildCompetitionSummary(result),
      researchInterests: _unique([
        ...result.understanding.directions,
        ...result.understanding.categories,
      ]),
      preferredLocations: const [],
      recommendationCount: result.recommendations.length,
      competitionResult: result,
    );
    final items = [
      item,
      ...list().where((current) => current.sessionId != result.sessionId),
    ]..sort(_byNewest);
    await _writeAll(items);
  }

  @override
  Future<void> remove(String sessionId) async {
    final items = list()
        .where((current) => current.sessionId != sessionId)
        .toList();
    await _writeAll(items);
  }

  @override
  Future<void> clear() => _writeAll(const []);

  void dispose() => _controller.close();

  List<SearchHistoryItem> _readAll() {
    final raw = _store.getJsonList(storageKey);
    if (raw == null) return const [];

    final items = <SearchHistoryItem>[];
    for (final entry in raw) {
      final item = _parseItem(entry);
      if (item != null) items.add(item);
    }
    items.sort(_byNewest);
    return items;
  }

  SearchHistoryItem? _parseItem(Object? entry) {
    if (entry is! Map) return null;
    final json = Map<String, dynamic>.from(entry);
    final sessionId = json['session_id'];
    final prompt = json['prompt'];
    final summary = json['summary'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final count = json['recommendation_count'];

    if (sessionId is! String ||
        sessionId.isEmpty ||
        prompt is! String ||
        prompt.isEmpty ||
        summary is! String ||
        createdAt == null ||
        count is! int) {
      return null;
    }

    final rawCompetitionResult = json['competition_result'];
    CompetitionRecommendationResult? competitionResult;
    if (rawCompetitionResult != null) {
      try {
        competitionResult = CompetitionRecommendationResultDto.fromJson(
          asJsonObject(rawCompetitionResult),
        ).toEntity();
      } catch (_) {
        competitionResult = null;
      }
    }

    return SearchHistoryItem(
      type: searchHistoryTypeFromString(json['type'] as String?),
      sessionId: sessionId,
      prompt: prompt,
      createdAt: createdAt,
      summary: summary,
      researchInterests:
          (json['research_interests'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      preferredLocations:
          (json['preferred_locations'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<String>()
              .toList(),
      recommendationCount: count,
      competitionResult: competitionResult,
    );
  }

  Future<void> _writeAll(List<SearchHistoryItem> items) async {
    await _store.setJsonList(
      storageKey,
      items.map(_toJson).toList(growable: false),
    );
    _controller.add(List<SearchHistoryItem>.unmodifiable(items));
  }

  Map<String, dynamic> _toJson(SearchHistoryItem item) => <String, dynamic>{
    'type': item.type.name,
    'session_id': item.sessionId,
    'prompt': item.prompt,
    'created_at': item.createdAt.toIso8601String(),
    'summary': item.summary,
    'research_interests': item.researchInterests,
    'preferred_locations': item.preferredLocations,
    'recommendation_count': item.recommendationCount,
    if (item.competitionResult != null)
      'competition_result': CompetitionRecommendationResultDto.fromEntity(
        item.competitionResult!,
      ).toJson(),
  };

  static String _buildSummary(RecommendationResult result) {
    final interests = result.queryUnderstanding.researchInterests;
    final locations = result.queryUnderstanding.preferredLocations;
    final parts = <String>[
      if (interests.isNotEmpty) '方向：${interests.join('、')}',
      if (locations.isNotEmpty) '地区：${locations.join('、')}',
    ];
    return parts.isEmpty ? '未识别出明确方向，可重推优化条件' : parts.join(' / ');
  }

  static String _buildCompetitionSummary(
    CompetitionRecommendationResult result,
  ) {
    final u = result.understanding;
    final parts = <String>[
      if (u.directions.isNotEmpty) '方向：${u.directions.join('、')}',
      if (u.categories.isNotEmpty) '类别：${u.categories.join('、')}',
      if (u.timingPreferences.isNotEmpty) '时间：${u.timingPreferences.join('、')}',
      if (u.teamPreferences.isNotEmpty) '组队：${u.teamPreferences.join('、')}',
    ];
    return parts.isEmpty ? '未识别出明确竞赛需求，可重推优化条件' : parts.join(' / ');
  }

  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || !seen.add(trimmed)) continue;
      out.add(trimmed);
    }
    return out;
  }

  static int _byNewest(SearchHistoryItem a, SearchHistoryItem b) =>
      b.createdAt.compareTo(a.createdAt);
}
