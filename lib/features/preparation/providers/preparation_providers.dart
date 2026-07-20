import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../data/http/http_preparation_config_repository.dart';
import '../../../data/http/http_preparation_level_diagnoser.dart';
import '../../../data/http/http_preparation_personalizer.dart';
import '../../../data/http/http_preparation_plan_assistant.dart';
import '../../../data/http/http_preparation_template_provider.dart';
import '../../../data/local/assistant_history_store.dart';
import '../../../data/local/level_diagnosis_store.dart';
import '../../../data/local/local_preparation_plan_repository.dart';
import '../../../domain/entities/preparation_config.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../../domain/repositories/preparation_config_repository.dart';
import '../../../domain/repositories/preparation_level_diagnoser.dart';
import '../../../domain/repositories/preparation_personalizer.dart';
import '../../../domain/repositories/preparation_plan_assistant.dart';
import '../../../domain/repositories/preparation_plan_repository.dart';
import '../../../domain/repositories/preparation_template_provider.dart';
import '../../../domain/services/preparation_plan_generator.dart';
import 'preparation_assistant_controller.dart';

final preparationPlanRepositoryProvider = Provider<PreparationPlanRepository>((
  ref,
) {
  final repo = LocalPreparationPlanRepository(ref.watch(localStoreProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final levelDiagnosisStoreProvider = Provider<LevelDiagnosisStore>(
  (ref) => LevelDiagnosisStore(ref.watch(localStoreProvider)),
);

final preparationConfigRepositoryProvider =
    Provider<PreparationConfigRepository>(
      (ref) => HttpPreparationConfigRepository(ref.watch(apiDioProvider)),
    );

final preparationConfigProvider = FutureProvider<PreparationConfig>((ref) {
  return ref.watch(preparationConfigRepositoryProvider).fetch();
});

final preparationTemplateProvider = Provider<PreparationTemplateProvider>(
  (ref) => HttpPreparationTemplateProvider(ref.watch(apiDioProvider)),
);

final preparationPersonalizerProvider = Provider<PreparationPersonalizer>(
  (ref) => HttpPreparationPersonalizer(ref.watch(apiDioProvider)),
);

final preparationLevelDiagnoserProvider = Provider<PreparationLevelDiagnoser>(
  (ref) => HttpPreparationLevelDiagnoser(ref.watch(apiDioProvider)),
);

final preparationPlanAssistantProvider = Provider<PreparationPlanAssistant>(
  (ref) => HttpPreparationPlanAssistant(ref.watch(apiDioProvider)),
);

final assistantHistoryStoreProvider = Provider<AssistantHistoryStore>(
  (ref) => AssistantHistoryStore(ref.watch(localStoreProvider)),
);

final preparationPlanGeneratorProvider = Provider<PreparationPlanGenerator>(
  (ref) => PreparationPlanGenerator(
    templateProvider: ref.watch(preparationTemplateProvider),
    personalizer: ref.watch(preparationPersonalizerProvider),
  ),
);

final preparationPlanListProvider = StreamProvider<List<PreparationPlan>>(
  (ref) => ref.watch(preparationPlanRepositoryProvider).watch(),
);

final activePlanForCompetitionProvider =
    Provider.family<PreparationPlan?, String>((ref, competitionId) {
      final repo = ref.watch(preparationPlanRepositoryProvider);
      return repo.activeForCompetition(competitionId);
    });

final preparationAssistantControllerProvider =
    NotifierProvider.family<
      PreparationAssistantController,
      PreparationAssistantControllerState,
      String
    >(PreparationAssistantController.new);
