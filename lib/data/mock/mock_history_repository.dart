import 'dart:async';

import '../../domain/entities/competition_recommendation_result.dart';
import '../../domain/entities/recommendation_result.dart';
import '../../domain/entities/search_history_item.dart';
import '../../domain/repositories/history_repository.dart';

/// 内存搜索历史仓储，模拟后端历史接口。
class MockHistoryRepository implements HistoryRepository {
  MockHistoryRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final List<SearchHistoryItem> _items = [];
  final StreamController<List<SearchHistoryItem>> _controller =
      StreamController<List<SearchHistoryItem>>.broadcast();

  @override
  List<SearchHistoryItem> list() => List.unmodifiable(_items);

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
    for (final item in _items) {
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
    await Future<void>.delayed(const Duration(milliseconds: 150));
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
      ..._items.where((current) => current.sessionId != result.sessionId),
    ]..sort(_byNewest);
    _items
      ..clear()
      ..addAll(items);
    _controller.add(list());
  }

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
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
      ..._items.where((current) => current.sessionId != result.sessionId),
    ]..sort(_byNewest);
    _items
      ..clear()
      ..addAll(items);
    _controller.add(list());
  }

  @override
  Future<void> remove(String sessionId) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _items.removeWhere((current) => current.sessionId == sessionId);
    _controller.add(list());
  }

  @override
  Future<void> clear() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _items.clear();
    _controller.add(list());
  }

  void dispose() => _controller.close();

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
