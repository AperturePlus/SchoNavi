import '../../domain/entities/search_history_item.dart';
import 'api_envelope.dart';
import 'competition_recommendation_dtos.dart';

class SearchHistoryItemDto {
  const SearchHistoryItemDto({
    required this.type,
    required this.sessionId,
    required this.prompt,
    required this.createdAt,
    required this.summary,
    required this.researchInterests,
    required this.preferredLocations,
    required this.recommendationCount,
    this.competitionResult,
  });

  final String type;
  final String sessionId;
  final String prompt;
  final DateTime createdAt;
  final String summary;
  final List<String> researchInterests;
  final List<String> preferredLocations;
  final int recommendationCount;
  final CompetitionRecommendationResultDto? competitionResult;

  factory SearchHistoryItemDto.fromJson(Map<String, dynamic> json) {
    final competitionResultJson = json['competition_result'];
    return SearchHistoryItemDto(
      type: json['type'] as String? ?? 'mentor',
      sessionId: json['session_id'] as String,
      prompt: json['prompt'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      summary: json['summary'] as String,
      researchInterests: stringList(json['research_interests']),
      preferredLocations: stringList(json['preferred_locations']),
      recommendationCount: json['recommendation_count'] as int,
      competitionResult: competitionResultJson == null
          ? null
          : CompetitionRecommendationResultDto.fromJson(
              asJsonObject(competitionResultJson),
            ),
    );
  }

  factory SearchHistoryItemDto.fromEntity(SearchHistoryItem item) {
    return SearchHistoryItemDto(
      type: item.type.name,
      sessionId: item.sessionId,
      prompt: item.prompt,
      createdAt: item.createdAt,
      summary: item.summary,
      researchInterests: item.researchInterests,
      preferredLocations: item.preferredLocations,
      recommendationCount: item.recommendationCount,
      competitionResult: item.competitionResult == null
          ? null
          : CompetitionRecommendationResultDto.fromEntity(
              item.competitionResult!,
            ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'session_id': sessionId,
    'prompt': prompt,
    'created_at': createdAt.toIso8601String(),
    'summary': summary,
    'research_interests': researchInterests,
    'preferred_locations': preferredLocations,
    'recommendation_count': recommendationCount,
    if (competitionResult != null)
      'competition_result': competitionResult!.toJson(),
  };

  SearchHistoryItem toEntity() => SearchHistoryItem(
    type: searchHistoryTypeFromString(type),
    sessionId: sessionId,
    prompt: prompt,
    createdAt: createdAt,
    summary: summary,
    researchInterests: researchInterests,
    preferredLocations: preferredLocations,
    recommendationCount: recommendationCount,
    competitionResult: competitionResult?.toEntity(),
  );
}
