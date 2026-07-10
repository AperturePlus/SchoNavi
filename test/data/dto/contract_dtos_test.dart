import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/data/dto/api_envelope.dart';
import 'package:scho_navi/data/dto/achievement_draft_dto.dart';
import 'package:scho_navi/data/dto/chat_dto.dart';
import 'package:scho_navi/data/dto/comparison_dto.dart';
import 'package:scho_navi/data/dto/competition_recommendation_dtos.dart';
import 'package:scho_navi/data/dto/email_draft_dto.dart';
import 'package:scho_navi/data/dto/favorite_dto.dart';
import 'package:scho_navi/data/dto/history_dto.dart';
import 'package:scho_navi/data/dto/home_prompt_dto.dart';
import 'package:scho_navi/data/dto/match_analysis_dto.dart';
import 'package:scho_navi/data/dto/professor_dto.dart';
import 'package:scho_navi/data/dto/profile_dtos.dart';
import 'package:scho_navi/data/dto/recommendation_dtos.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';

void main() {
  test('UserProfileDto round-trips fixture and maps entities', () {
    final fixture = _fixture('profile_success.json');
    final data = decodeEnvelope(
      fixture,
      (data) => UserProfileDto.fromJson(asJsonObject(data)),
    );

    expect(data.toJson(), equals(fixture['data']));
    final profile = data.toEntity();
    expect(profile.gender, Gender.undisclosed);
    expect(profile.score?.gpa, 3.8);
    expect(profile.competitions.single.award, '二等奖');
    expect(profile.research.single.venueOrStatus, '结题');

    final dto = UserProfileDto.fromEntity(profile);
    expect(dto.toJson(), equals(fixture['data']));
  });

  test('FavoriteItemDto round-trips date and maps entity', () {
    final json = <String, dynamic>{
      'professor_id': 'p_001',
      'name': '张三',
      'university': '上海交通大学',
      'college': '电子信息与电气工程学院',
      'title': '教授',
      'research_fields': ['医学影像'],
      'homepage_url': 'https://example.edu.cn',
      'favorited_at': '2026-06-15T10:00:00.000Z',
    };

    final dto = FavoriteItemDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().favoritedAt.toUtc().year, 2026);
  });

  test('SearchHistoryItemDto round-trips full contract shape', () {
    final mentorJson = <String, dynamic>{
      'type': 'mentor',
      'session_id': 's_1',
      'prompt': '医学影像 上海',
      'created_at': '2026-06-15T10:00:00.000Z',
      'summary': '方向：医学影像 / 地区：上海',
      'research_interests': ['医学影像'],
      'preferred_locations': ['上海'],
      'recommendation_count': 3,
    };

    final mentorDto = SearchHistoryItemDto.fromJson(mentorJson);
    expect(mentorDto.toJson(), equals(mentorJson));
    expect(mentorDto.toEntity().type, SearchHistoryType.mentor);
    expect(
      mentorDto.toEntity().createdAt.toUtc(),
      DateTime.utc(2026, 6, 15, 10),
    );

    final item = SearchHistoryItem(
      type: SearchHistoryType.competition,
      sessionId: 'c_1',
      prompt: '数学建模',
      createdAt: DateTime.utc(2026, 6, 15, 10),
      summary: '方向：数学建模',
      researchInterests: const ['数学建模'],
      preferredLocations: const [],
      recommendationCount: 1,
      competitionResult: _competitionResult,
    );

    final dto = SearchHistoryItemDto.fromEntity(item);
    expect(dto.toJson(), {
      'type': 'competition',
      'session_id': 'c_1',
      'prompt': '数学建模',
      'created_at': '2026-06-15T10:00:00.000Z',
      'summary': '方向：数学建模',
      'research_interests': ['数学建模'],
      'preferred_locations': <String>[],
      'recommendation_count': 1,
      'competition_result': _competitionResultJson,
    });
    expect(dto.toEntity().type, SearchHistoryType.competition);
    final roundTripped = SearchHistoryItemDto.fromJson(dto.toJson()).toEntity();
    expect(roundTripped.competitionResult?.sessionId, 'c_1');
    expect(
      roundTripped.competitionResult?.recommendations.single.name,
      '人工智能创新应用大赛',
    );
  });

  test('CompetitionRecommendationResultDto round-trips', () {
    final json = <String, dynamic>{
      'session_id': 'c_123',
      'understanding': {
        'directions': ['人工智能'],
        'categories': ['计算机类'],
        'timing_preferences': ['近期可报名'],
        'team_preferences': ['团队赛'],
        'uncertainties': ['未明确可投入时间'],
      },
      'recommendations': [
        {
          'id': 'comp_ai',
          'name': '人工智能创新应用大赛',
          'category': '计算机类',
          'level': '国家级',
          'tags': ['AI', '应用'],
          'team_size': '1-5人',
          'signup_time': '以官网通知为准',
          'contest_time': '以官网通知为准',
          'format': '作品赛',
          'organizer': '主办方',
          'official_url': 'https://example.com',
          'reason': '方向匹配。',
          'preparation_tips': ['先确定应用场景'],
          'limitations': ['以官网最新通知为准'],
          'match_score': 0.86,
        },
      ],
      'follow_up_questions': ['算法赛', '作品赛'],
    };

    final dto = CompetitionRecommendationResultDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().recommendations.single.matchScore, 0.86);
  });

  test(
    'CompetitionRecommendationResultDto hides technical understanding keys',
    () {
      final json = <String, dynamic>{
        'session_id': 'c_technical',
        'understanding': {
          'directions': ['AI', 'major'],
          'categories': ['portfolio', '计算机类'],
          'timing_preferences': ['portfolio'],
          'team_preferences': ['team_preference', 'team'],
          'uncertainties': [
            'major',
            'grade',
            'experience_level',
            'team_preference',
          ],
        },
        'recommendations': <Map<String, dynamic>>[],
        'follow_up_questions': <String>[],
      };

      final data = CompetitionRecommendationResultDto.fromJson(json).toEntity();
      final visible = [
        ...data.understanding.directions,
        ...data.understanding.categories,
        ...data.understanding.timingPreferences,
        ...data.understanding.teamPreferences,
        ...data.understanding.uncertainties,
      ];

      expect(visible, isNot(contains('portfolio')));
      expect(visible, isNot(contains('major')));
      expect(visible, isNot(contains('grade')));
      expect(visible, isNot(contains('experience_level')));
      expect(visible, isNot(contains('team_preference')));
      expect(data.understanding.directions, ['AI']);
      expect(data.understanding.categories, ['计算机类']);
      expect(data.understanding.timingPreferences, isEmpty);
      expect(data.understanding.teamPreferences, ['团队赛']);
      expect(
        data.understanding.uncertainties,
        containsAll(['未明确专业', '未明确年级', '未明确竞赛经验', '未明确组队偏好']),
      );
    },
  );

  test('ChatMessageResponseDto round-trips recommendation payload', () {
    final json = <String, dynamic>{
      'session_id': 's_123',
      'answer': '主要依据是研究方向匹配。',
      'related_recommendations': [_recommendationJson],
    };

    final dto = ChatMessageResponseDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().relatedRecommendations.single.professorId, 'p_001');
  });

  test('ComparisonReportDto round-trips nested professors and cells', () {
    final json = <String, dynamic>{
      'professor_ids': ['p_001', 'p_002'],
      'professors': [_professorJson('p_001'), _professorJson('p_002')],
      'rows': [
        {
          'dimension': '研究方向匹配',
          'cells': {'p_001': '偏医学影像', 'p_002': '偏大模型'},
        },
      ],
      'summary': '两位导师方向不同。',
      'suggestion': '若更看重医学影像可优先了解 p_001。',
    };

    final dto = ComparisonReportDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().rows.single.cells['p_002'], '偏大模型');
  });

  test('MatchAnalysisDto round-trips dimensions', () {
    final json = <String, dynamic>{
      'professor_id': 'p_001',
      'summary': '方向较契合。',
      'strengths': ['项目经历相关'],
      'gaps': ['需要补充论文阅读'],
      'suggestions': ['阅读导师近三年论文'],
      'dimensions': [
        {'label': '方向契合', 'score': 82, 'comment': '研究兴趣接近。'},
      ],
    };

    final dto = MatchAnalysisDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().overallScore, 82);
  });

  test('EmailDraftDto round-trips', () {
    final json = <String, dynamic>{
      'subject': '关于医学影像方向研究生申请的咨询',
      'body': '张三教授您好...',
    };

    final dto = EmailDraftDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().subject, contains('医学影像'));
  });

  test('AchievementDraftDto round-trips competitions and research', () {
    final json = <String, dynamic>{
      'competitions': [
        {'name': '数学建模竞赛', 'level': '省级', 'award': '一等奖'},
      ],
      'research': [
        {
          'type': 'paper',
          'title': '医学影像论文',
          'role': '第一作者',
          'venue_or_status': '在投',
          'year': '2026',
        },
      ],
    };

    final dto = AchievementDraftDto.fromJson(json);
    expect(dto.toJson(), equals(json));
    expect(dto.toEntity().research.single.title, '医学影像论文');
  });

  test(
    'HomePromptDto, ProfessorDto and RecommendationDto round-trip basics',
    () {
      expect(HomePromptDto.fromJson({'text': '推荐近期竞赛'}).toJson(), {
        'text': '推荐近期竞赛',
      });
      expect(
        ProfessorDto.fromJson(_professorJson('p_001')).toJson(),
        equals(_professorJson('p_001')),
      );
      expect(
        RecommendationDto.fromJson(_recommendationJson).toJson(),
        equals(_recommendationJson),
      );
    },
  );

  test('decodeEnvelope surfaces backend message for non-zero code', () {
    final fixture = _fixture('envelope_error.json');

    expect(
      () => decodeEnvelope(fixture, (data) => data),
      throwsA(isA<ValidationException>()),
    );
  });
}

Map<String, dynamic> _fixture(String name) {
  final text = File('test/fixtures/api/$name').readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

Map<String, dynamic> _professorJson(String id) => <String, dynamic>{
  'professor_id': id,
  'name': '张三',
  'university': '上海交通大学',
  'college': '电子信息与电气工程学院',
  'title': '教授',
  'research_fields': ['医学影像', '计算机视觉'],
};

final _recommendationJson = <String, dynamic>{
  'professor_id': 'p_001',
  'name': '张三',
  'university': '上海交通大学',
  'college': '电子信息与电气工程学院',
  'title': '教授',
  'research_fields': ['医学影像', '计算机视觉'],
  'homepage_url': 'https://example.edu.cn/zhangsan',
  'match_level': '高',
  'match_score': 0.92,
  'reason': '研究方向与用户需求高度相关。',
  'limitations': ['招生信息以学校官网为准'],
};

const _competitionResult = CompetitionRecommendationResult(
  sessionId: 'c_1',
  understanding: CompetitionQueryUnderstanding(
    directions: ['人工智能'],
    categories: ['计算机类'],
    timingPreferences: ['近期可报名'],
    teamPreferences: ['团队赛'],
    uncertainties: ['未明确可投入时间'],
  ),
  recommendations: [
    RecommendedCompetition(
      id: 'comp_ai',
      name: '人工智能创新应用大赛',
      category: '计算机类',
      level: '国家级',
      tags: ['AI', '应用'],
      teamSize: '1-5人',
      signupTime: '以官网通知为准',
      contestTime: '以官网通知为准',
      format: '作品赛',
      organizer: '主办方',
      officialUrl: 'https://example.com',
      reason: '方向匹配。',
      preparationTips: ['先确定应用场景'],
      limitations: ['以官网最新通知为准'],
      matchScore: 0.86,
    ),
  ],
  followUpQuestions: ['算法赛', '作品赛'],
);

final _competitionResultJson = <String, dynamic>{
  'session_id': 'c_1',
  'understanding': {
    'directions': ['人工智能'],
    'categories': ['计算机类'],
    'timing_preferences': ['近期可报名'],
    'team_preferences': ['团队赛'],
    'uncertainties': ['未明确可投入时间'],
  },
  'recommendations': [
    {
      'id': 'comp_ai',
      'name': '人工智能创新应用大赛',
      'category': '计算机类',
      'level': '国家级',
      'tags': ['AI', '应用'],
      'team_size': '1-5人',
      'signup_time': '以官网通知为准',
      'contest_time': '以官网通知为准',
      'format': '作品赛',
      'organizer': '主办方',
      'official_url': 'https://example.com',
      'reason': '方向匹配。',
      'preparation_tips': ['先确定应用场景'],
      'limitations': ['以官网最新通知为准'],
      'match_score': 0.86,
    },
  ],
  'follow_up_questions': ['算法赛', '作品赛'],
};
