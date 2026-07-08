import '../entities/competition_query_understanding.dart';

enum _UnderstandingField { directions, categories, timing, team }

class CompetitionQueryUnderstandingNormalizer {
  const CompetitionQueryUnderstandingNormalizer._();

  static CompetitionQueryUnderstanding normalize(
    CompetitionQueryUnderstanding input,
  ) {
    return CompetitionQueryUnderstanding(
      directions: _normalizeValues(
        input.directions,
        _UnderstandingField.directions,
      ),
      categories: _normalizeValues(
        input.categories,
        _UnderstandingField.categories,
      ),
      timingPreferences: _normalizeValues(
        input.timingPreferences,
        _UnderstandingField.timing,
      ),
      teamPreferences: _normalizeValues(
        input.teamPreferences,
        _UnderstandingField.team,
      ),
      uncertainties: _normalizeUncertainties(input.uncertainties),
    );
  }

  static List<String> _normalizeValues(
    List<String> values,
    _UnderstandingField field,
  ) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in values) {
      final display = _displayValue(raw, field);
      if (display == null) continue;
      final key = display.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(display);
    }
    return List.unmodifiable(out);
  }

  static List<String> _normalizeUncertainties(List<String> values) {
    final seen = <String>{};
    final out = <String>[];
    for (final raw in values) {
      final text = _clean(raw);
      if (text == null) continue;

      final key = _key(text);
      final display = _uncertaintyLabels[key];
      final normalized = display ?? (_shouldDrop(text, key) ? null : text);
      if (normalized == null) continue;
      if (!seen.add(normalized)) continue;
      out.add(normalized);
    }
    return List.unmodifiable(out);
  }

  static String? _displayValue(String raw, _UnderstandingField field) {
    final text = _clean(raw);
    if (text == null) return null;

    final key = _key(text);
    final mapped = _fieldValueLabels[field]?[key];
    if (mapped != null) return mapped;
    if (_shouldDrop(text, key)) return null;
    return text;
  }

  static bool _shouldDrop(String text, String key) {
    return _schemaTokens.contains(key) || _isTechnicalToken(text);
  }

  static String? _clean(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }

  static String _key(String text) {
    final withSnakeCase = text.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (match) => '${match.group(1)}_${match.group(2)}',
    );
    return withSnakeCase
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAll(RegExp(r'__+'), '_')
        .toLowerCase();
  }

  static bool _isTechnicalToken(String text) {
    if (_containsChinese.hasMatch(text)) return false;
    return _snakeToken.hasMatch(text) ||
        _lowerToken.hasMatch(text) ||
        _camelToken.hasMatch(text);
  }

  static final RegExp _containsChinese = RegExp(r'[\u4e00-\u9fff]');
  static final RegExp _snakeToken = RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$');
  static final RegExp _lowerToken = RegExp(r'^[a-z][a-z0-9]*$');
  static final RegExp _camelToken = RegExp(r'^[a-z]+(?:[A-Z][a-z0-9]*)+$');

  static const Map<String, String> _uncertaintyLabels = {
    'directions': '未明确竞赛方向',
    'categories': '未明确竞赛类别',
    'major': '未明确专业',
    'grade': '未明确年级',
    'experience_level': '未明确竞赛经验',
    'team_preference': '未明确组队偏好',
    'team_preferences': '未明确组队偏好',
    'time_commitment': '未明确可投入时间',
    'weekly_commitment': '未明确可投入时间',
    'timing_preferences': '未明确参赛时间偏好',
    'portfolio': '未明确项目/作品经历',
  };

  static const Set<String> _schemaTokens = {
    'understanding',
    'query_understanding',
    'directions',
    'categories',
    'timing_preferences',
    'timingpreferences',
    'team_preferences',
    'teampreferences',
    'uncertainties',
    'recommendations',
    'follow_up_questions',
    'followupquestions',
    'profile',
    'portfolio',
    'major',
    'grade',
    'experience_level',
    'experiencelevel',
    'team_preference',
    'teampreference',
    'time_commitment',
    'timecommitment',
    'weekly_commitment',
    'weeklycommitment',
  };

  static const Map<_UnderstandingField, Map<String, String>> _fieldValueLabels =
      {
        _UnderstandingField.directions: {
          'ai': 'AI',
          'cv': 'CV',
          'nlp': 'NLP',
          'icpc': 'ICPC',
          'ai4s': 'AI4S',
          'algorithm': '算法',
          'algorithms': '算法',
          'artificial_intelligence': '人工智能',
          'math_modeling': '数学建模',
          'mathematical_modeling': '数学建模',
          'data_science': '数据科学',
        },
        _UnderstandingField.categories: {
          'cs': '计算机类',
          'computer': '计算机类',
          'computer_science': '计算机类',
          'science': '理学类',
          'engineering': '工科类',
          'business': '商科类',
          'design': '设计类',
        },
        _UnderstandingField.timing: {
          'recent': '近期可报名',
          'near_term': '近期可报名',
          'short_term': '近期可报名',
          'flexible': '时间灵活',
          'no_preference': '时间灵活',
        },
        _UnderstandingField.team: {
          'team': '团队赛',
          'team_contest': '团队赛',
          'teamwork': '团队赛',
          'group': '团队赛',
          'individual': '个人赛',
          'personal': '个人赛',
          'solo': '个人赛',
          'alone': '个人赛',
          'flexible': '组队灵活',
          'no_preference': '组队灵活',
        },
      };
}
