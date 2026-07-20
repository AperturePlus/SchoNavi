import '../../domain/entities/preparation_plan.dart';
import '../../domain/repositories/preparation_level_diagnoser.dart';
import 'profile_dtos.dart';

/// 序列化 [LevelDiagnosisRequest] 为 HTTP 请求体（spec §3.2 结构）。
Map<String, dynamic> levelDiagnosisRequestToJson(LevelDiagnosisRequest req) {
  return <String, dynamic>{
    'competition': req.competition.toJson(),
    if (req.profile != null && !req.profile!.isEmpty)
      'profile': UserProfileDto.fromEntity(req.profile!).toJson(),
    'answers': req.answers
        .map(
          (a) => <String, dynamic>{
            'question_key': a.questionKey,
            'answer': a.answer,
          },
        )
        .toList(),
  };
}

/// DTO：从后端返回的 JSON `data` 解码为 [LevelDiagnosisSuggestion]。
///
/// 解码同时承担 spec §5.1 的校验职责（与 `AiPreparationLevelDiagnoser` 共用）：
/// - `level` 必须是 beginner|intermediate|experienced 之一，否则抛
///   [FormatException]，由调用方兜底转 `Failure(ServerException)`。
/// - 整体结构非对象 → 抛 [FormatException]。
class LevelDiagnosisSuggestionDto {
  LevelDiagnosisSuggestionDto({
    required this.level,
    required this.rationale,
    this.suggestion,
  });

  final ExperienceLevel level;
  final String rationale;
  final String? suggestion;

  factory LevelDiagnosisSuggestionDto.fromJson(Map<String, dynamic> json) {
    final rawLevel = json['level']?.toString().trim();
    final level = _parseLevel(rawLevel);
    if (level == null) {
      throw FormatException('invalid experience level: $rawLevel');
    }
    return LevelDiagnosisSuggestionDto(
      level: level,
      rationale: json['rationale']?.toString().trim() ?? '',
      suggestion: _optionalString(json['suggestion']),
    );
  }

  LevelDiagnosisSuggestion toEntity() => LevelDiagnosisSuggestion(
    level: level,
    rationale: rationale,
    suggestion: suggestion,
  );

  static ExperienceLevel? _parseLevel(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final value in ExperienceLevel.values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  static String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }
}
