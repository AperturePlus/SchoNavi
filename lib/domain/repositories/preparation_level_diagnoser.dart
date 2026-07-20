import '../../core/result/result.dart';
import '../entities/preparation_plan.dart';
import '../entities/user_profile.dart';

/// 水平诊断请求：携带竞赛快照、可选学生档案与两个问答答案。供
/// 由 HTTP 后端实现消费。
class LevelDiagnosisRequest {
  const LevelDiagnosisRequest({
    required this.competition,
    required this.answers,
    this.profile,
  });

  final CompetitionSnapshot competition;

  /// 两个问答答案（question_key → answer）。
  final List<DiagnosisAnswer> answers;

  final UserProfile? profile;
}

/// 单条诊断问答答案。
class DiagnosisAnswer {
  const DiagnosisAnswer({required this.questionKey, required this.answer});

  final String questionKey;
  final String answer;
}

/// 水平诊断建议（spec §3.2 response data）：AI 建议档位 + 理由 + 排期建议。
/// 仅为 AI 建议，需用户接受或手动覆盖后才写入 `LevelDiagnosisStore`。
class LevelDiagnosisSuggestion {
  const LevelDiagnosisSuggestion({
    required this.level,
    required this.rationale,
    this.suggestion,
  });

  final ExperienceLevel level;
  final String rationale;
  final String? suggestion;

  @override
  String toString() =>
      'LevelDiagnosisSuggestion(level: $level, rationale: $rationale, '
      'suggestion: $suggestion)';
}

/// 备赛水平诊断器：根据竞赛快照、可选学生档案与两个问答答案，
/// 判断用户在该类赛事上的经验等级（仅 AI 建议，需用户确认后写入 store）。

abstract interface class PreparationLevelDiagnoser {
  Future<Result<LevelDiagnosisSuggestion>> diagnose(
    LevelDiagnosisRequest request,
  );
}
