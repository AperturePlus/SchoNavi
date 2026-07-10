import '../../core/result/result.dart';
import '../../data/dto/preparation_plan_dtos.dart';

export '../../data/dto/preparation_plan_dtos.dart'
    show
        PreparationPersonalizationRequest,
        PreparationPersonalizationResult,
        PreparationPhasePersonalization,
        PreparationOptionalTaskSuggestion;

/// 备赛计划个性化器的后端契约。
abstract interface class PreparationPersonalizer {
  Future<Result<PreparationPersonalizationResult>> personalize({
    required PreparationPersonalizationRequest req,
  });
}
