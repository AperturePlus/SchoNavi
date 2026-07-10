import '../entities/preparation_plan.dart';

abstract interface class PreparationPlanRepository {
  List<PreparationPlan> list();
  PreparationPlan? findById(String id);
  PreparationPlan? activeForCompetition(String competitionId);
  Stream<List<PreparationPlan>> watch();
  Future<PreparationPlan> save(PreparationPlan plan);
  Future<void> archive(String id);
  Future<void> delete(String id);
  Future<void> clearAll();
}
