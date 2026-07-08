import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/result/result.dart';
import '../../core/error/app_exception.dart';
import '../../domain/entities/competition_recommendation_result.dart';
import '../../domain/entities/recommendation_result.dart';
import '../../domain/entities/search_history_item.dart';
import '../../domain/repositories/history_repository.dart';
import '../dto/api_envelope.dart';
import '../dto/history_dto.dart';

class HttpHistoryRepository implements HistoryRepository {
  HttpHistoryRepository(this._dio, {DateTime Function()? now, this.onSyncError})
    : _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;
  final void Function(AppException)? onSyncError;
  final StreamController<List<SearchHistoryItem>> _controller =
      StreamController<List<SearchHistoryItem>>.broadcast();
  List<SearchHistoryItem> _snapshot = const [];

  @override
  List<SearchHistoryItem> list() {
    _refresh();
    return _snapshot;
  }

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
    final cached = _findSnapshot(sessionId, type: type);
    if (cached != null &&
        (type != SearchHistoryType.competition ||
            cached.competitionResult != null)) {
      return cached;
    }

    final result = await guardApi(
      () => _dio.get<dynamic>(
        '/api/v1/history/${Uri.encodeComponent(sessionId)}',
        queryParameters: type == null
            ? null
            : <String, dynamic>{'type': type.name},
      ),
      (data) => SearchHistoryItemDto.fromJson(asJsonObject(data)).toEntity(),
    );
    return switch (result) {
      Success<SearchHistoryItem>(:final data) => () {
        if (type != null && data.type != type) return null;
        _setSnapshot(
          [
            data,
            ..._snapshot.where(
              (current) => current.sessionId != data.sessionId,
            ),
          ]..sort(_byNewest),
        );
        return data;
      }(),
      Failure<SearchHistoryItem>(:final error) => throw error,
    };
  }

  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) {
    return _add(
      SearchHistoryItem(
        type: SearchHistoryType.mentor,
        sessionId: result.sessionId,
        prompt: prompt,
        createdAt: _now(),
        summary: _mentorSummary(result),
        researchInterests: result.queryUnderstanding.researchInterests,
        preferredLocations: result.queryUnderstanding.preferredLocations,
        recommendationCount: result.recommendations.length,
      ),
    );
  }

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) {
    return _add(
      SearchHistoryItem(
        type: SearchHistoryType.competition,
        sessionId: result.sessionId,
        prompt: prompt,
        createdAt: _now(),
        summary: _competitionSummary(result),
        researchInterests: _unique([
          ...result.understanding.directions,
          ...result.understanding.categories,
        ]),
        preferredLocations: const [],
        recommendationCount: result.recommendations.length,
        competitionResult: result,
      ),
    );
  }

  @override
  Future<void> remove(String sessionId) async {
    final result = await guardApi(
      () => _dio.delete<dynamic>('/api/v1/history/$sessionId'),
      (_) => true,
    );
    if (result case Failure<bool>(:final error)) throw error;
    _setSnapshot(
      _snapshot
          .where((current) => current.sessionId != sessionId)
          .toList(growable: false),
    );
  }

  @override
  Future<void> clear() async {
    final result = await guardApi(
      () => _dio.delete<dynamic>('/api/v1/history'),
      (_) => true,
    );
    if (result case Failure<bool>(:final error)) throw error;
    _setSnapshot(const []);
  }

  void dispose() => _controller.close();

  Future<void> _add(SearchHistoryItem item) async {
    final result = await guardApi(
      () => _dio.post<dynamic>(
        '/api/v1/history',
        data: SearchHistoryItemDto.fromEntity(item).toJson(),
      ),
      (data) => SearchHistoryItemDto.fromJson(asJsonObject(data)).toEntity(),
    );
    final saved = switch (result) {
      Success<SearchHistoryItem>(:final data) => data,
      Failure<SearchHistoryItem>(:final error) => throw error,
    };
    _setSnapshot(
      [
        saved,
        ..._snapshot.where((current) => current.sessionId != saved.sessionId),
      ]..sort(_byNewest),
    );
  }

  Future<void> _refresh() async {
    final result = await guardApi(
      () => _dio.get<dynamic>('/api/v1/history'),
      (data) => (data as List<dynamic>? ?? const <dynamic>[])
          .map(
            (item) =>
                SearchHistoryItemDto.fromJson(asJsonObject(item)).toEntity(),
          )
          .toList(growable: false),
    );
    if (result is Success<List<SearchHistoryItem>>) {
      _setSnapshot(result.data..sort(_byNewest));
    } else if (result case Failure<List<SearchHistoryItem>>(:final error)) {
      onSyncError?.call(error);
    }
  }

  void _setSnapshot(List<SearchHistoryItem> items) {
    _snapshot = List<SearchHistoryItem>.unmodifiable(items);
    if (!_controller.isClosed) _controller.add(_snapshot);
  }

  SearchHistoryItem? _findSnapshot(
    String sessionId, {
    SearchHistoryType? type,
  }) {
    for (final item in _snapshot) {
      if (item.sessionId == sessionId && (type == null || item.type == type)) {
        return item;
      }
    }
    return null;
  }

  static String _mentorSummary(RecommendationResult result) {
    final interests = result.queryUnderstanding.researchInterests;
    final locations = result.queryUnderstanding.preferredLocations;
    final parts = <String>[
      if (interests.isNotEmpty) '方向：${interests.join('、')}',
      if (locations.isNotEmpty) '地区：${locations.join('、')}',
    ];
    return parts.isEmpty ? '未识别出明确方向，可重推优化条件' : parts.join(' / ');
  }

  static String _competitionSummary(CompetitionRecommendationResult result) {
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
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
    ];
  }

  static int _byNewest(SearchHistoryItem a, SearchHistoryItem b) =>
      b.createdAt.compareTo(a.createdAt);
}
