import '../entities/competition_recommendation_result.dart';
import '../entities/recommendation_result.dart';
import '../entities/search_history_item.dart';

abstract interface class HistoryRepository {
  List<SearchHistoryItem> list();
  Stream<List<SearchHistoryItem>> watch();
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  });
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  });
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  });
  Future<void> remove(String sessionId);
  Future<void> clear();
}
