import '../../domain/entities/competition_query_understanding.dart';
import '../../domain/entities/competition_recommendation_result.dart';
import '../../domain/entities/recommended_competition.dart';
import '../../domain/services/competition_query_understanding_normalizer.dart';
import 'api_envelope.dart';

class CompetitionQueryUnderstandingDto {
  const CompetitionQueryUnderstandingDto({
    required this.directions,
    required this.categories,
    required this.timingPreferences,
    required this.teamPreferences,
    required this.uncertainties,
  });

  final List<String> directions;
  final List<String> categories;
  final List<String> timingPreferences;
  final List<String> teamPreferences;
  final List<String> uncertainties;

  factory CompetitionQueryUnderstandingDto.fromJson(Map<String, dynamic> json) {
    return CompetitionQueryUnderstandingDto(
      directions: stringList(json['directions']),
      categories: stringList(json['categories']),
      timingPreferences: stringList(json['timing_preferences']),
      teamPreferences: stringList(json['team_preferences']),
      uncertainties: stringList(json['uncertainties']),
    );
  }

  factory CompetitionQueryUnderstandingDto.fromEntity(
    CompetitionQueryUnderstanding item,
  ) {
    return CompetitionQueryUnderstandingDto(
      directions: item.directions,
      categories: item.categories,
      timingPreferences: item.timingPreferences,
      teamPreferences: item.teamPreferences,
      uncertainties: item.uncertainties,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'directions': directions,
    'categories': categories,
    'timing_preferences': timingPreferences,
    'team_preferences': teamPreferences,
    'uncertainties': uncertainties,
  };

  CompetitionQueryUnderstanding toEntity() =>
      CompetitionQueryUnderstandingNormalizer.normalize(
        CompetitionQueryUnderstanding(
          directions: directions,
          categories: categories,
          timingPreferences: timingPreferences,
          teamPreferences: teamPreferences,
          uncertainties: uncertainties,
        ),
      );
}

class RecommendedCompetitionDto {
  const RecommendedCompetitionDto({
    required this.id,
    required this.name,
    required this.category,
    required this.level,
    required this.tags,
    required this.teamSize,
    required this.signupTime,
    required this.contestTime,
    required this.format,
    required this.organizer,
    required this.reason,
    required this.preparationTips,
    required this.limitations,
    required this.matchScore,
    this.officialUrl,
  });

  final String id;
  final String name;
  final String category;
  final String level;
  final List<String> tags;
  final String teamSize;
  final String signupTime;
  final String contestTime;
  final String format;
  final String organizer;
  final String? officialUrl;
  final String reason;
  final List<String> preparationTips;
  final List<String> limitations;
  final double matchScore;

  factory RecommendedCompetitionDto.fromJson(Map<String, dynamic> json) {
    return RecommendedCompetitionDto(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      level: json['level'] as String,
      tags: stringList(json['tags']),
      teamSize: json['team_size'] as String,
      signupTime: json['signup_time'] as String,
      contestTime: json['contest_time'] as String,
      format: json['format'] as String,
      organizer: json['organizer'] as String,
      officialUrl: json['official_url'] as String?,
      reason: json['reason'] as String,
      preparationTips: stringList(json['preparation_tips']),
      limitations: stringList(json['limitations']),
      matchScore: (json['match_score'] as num).toDouble(),
    );
  }

  factory RecommendedCompetitionDto.fromEntity(RecommendedCompetition item) {
    return RecommendedCompetitionDto(
      id: item.id,
      name: item.name,
      category: item.category,
      level: item.level,
      tags: item.tags,
      teamSize: item.teamSize,
      signupTime: item.signupTime,
      contestTime: item.contestTime,
      format: item.format,
      organizer: item.organizer,
      officialUrl: item.officialUrl,
      reason: item.reason,
      preparationTips: item.preparationTips,
      limitations: item.limitations,
      matchScore: item.matchScore,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'category': category,
    'level': level,
    'tags': tags,
    'team_size': teamSize,
    'signup_time': signupTime,
    'contest_time': contestTime,
    'format': format,
    'organizer': organizer,
    if (officialUrl != null) 'official_url': officialUrl,
    'reason': reason,
    'preparation_tips': preparationTips,
    'limitations': limitations,
    'match_score': matchScore,
  };

  RecommendedCompetition toEntity() => RecommendedCompetition(
    id: id,
    name: name,
    category: category,
    level: level,
    tags: tags,
    teamSize: teamSize,
    signupTime: signupTime,
    contestTime: contestTime,
    format: format,
    organizer: organizer,
    officialUrl: officialUrl,
    reason: reason,
    preparationTips: preparationTips,
    limitations: limitations,
    matchScore: matchScore,
  );
}

class CompetitionRecommendationResultDto {
  const CompetitionRecommendationResultDto({
    required this.sessionId,
    required this.understanding,
    required this.recommendations,
    required this.followUpQuestions,
  });

  final String sessionId;
  final CompetitionQueryUnderstandingDto understanding;
  final List<RecommendedCompetitionDto> recommendations;
  final List<String> followUpQuestions;

  factory CompetitionRecommendationResultDto.fromJson(
    Map<String, dynamic> json,
  ) {
    return CompetitionRecommendationResultDto(
      sessionId: json['session_id'] as String,
      understanding: CompetitionQueryUnderstandingDto.fromJson(
        asJsonObject(json['understanding']),
      ),
      recommendations:
          (json['recommendations'] as List<dynamic>? ?? const <dynamic>[])
              .map(
                (item) =>
                    RecommendedCompetitionDto.fromJson(asJsonObject(item)),
              )
              .toList(growable: false),
      followUpQuestions: stringList(json['follow_up_questions']),
    );
  }

  factory CompetitionRecommendationResultDto.fromEntity(
    CompetitionRecommendationResult item,
  ) {
    return CompetitionRecommendationResultDto(
      sessionId: item.sessionId,
      understanding: CompetitionQueryUnderstandingDto.fromEntity(
        item.understanding,
      ),
      recommendations: item.recommendations
          .map(RecommendedCompetitionDto.fromEntity)
          .toList(growable: false),
      followUpQuestions: item.followUpQuestions,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'session_id': sessionId,
    'understanding': understanding.toJson(),
    'recommendations': recommendations.map((item) => item.toJson()).toList(),
    'follow_up_questions': followUpQuestions,
  };

  CompetitionRecommendationResult toEntity() => CompetitionRecommendationResult(
    sessionId: sessionId,
    understanding: understanding.toEntity(),
    recommendations: recommendations.map((item) => item.toEntity()).toList(),
    followUpQuestions: followUpQuestions,
  );
}
