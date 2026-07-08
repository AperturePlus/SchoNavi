import 'competition_recommendation_result.dart';

enum SearchHistoryType { mentor, competition }

SearchHistoryType searchHistoryTypeFromString(String? raw) => switch (raw) {
  'competition' => SearchHistoryType.competition,
  _ => SearchHistoryType.mentor,
};

/// 本地搜索历史快照。
class SearchHistoryItem {
  const SearchHistoryItem({
    this.type = SearchHistoryType.mentor,
    required this.sessionId,
    required this.prompt,
    required this.createdAt,
    required this.summary,
    required this.researchInterests,
    required this.preferredLocations,
    required this.recommendationCount,
    this.competitionResult,
  });

  final SearchHistoryType type;
  final String sessionId;
  final String prompt;
  final DateTime createdAt;
  final String summary;
  final List<String> researchInterests;
  final List<String> preferredLocations;
  final int recommendationCount;
  final CompetitionRecommendationResult? competitionResult;
}
