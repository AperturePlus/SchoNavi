import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_repository.dart';
import 'package:scho_navi/domain/services/preparation_reminder_builder.dart';
import 'package:scho_navi/features/preparation/providers/preparation_reminder_providers.dart';
import 'package:scho_navi/features/preparation/services/complete_notification_task_use_case.dart';

class _FakeRepo implements PreparationPlanRepository {
  _FakeRepo(this._plans);
  final List<PreparationPlan> _plans;
  @override
  List<PreparationPlan> list() => _plans;
  @override
  PreparationPlan? findById(String id) =>
      _plans.where((p) => p.id == id).firstOrNull;
  @override
  PreparationPlan? activeForCompetition(String competitionId) => null;
  @override
  Stream<List<PreparationPlan>> watch() => const Stream.empty();
  @override
  Future<PreparationPlan> save(PreparationPlan plan) async {
    final i = _plans.indexWhere((p) => p.id == plan.id);
    if (i >= 0) _plans[i] = plan;
    return plan;
  }

  @override
  Future<void> archive(String id) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> clearAll() async {}
}

PreparationTask _t(String id) => PreparationTask(
  id: id,
  title: 't$id',
  kind: PreparationTaskKind.required,
  estimatedHours: 1,
  dueDate: DateTime(2026, 7, 2),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('handler returns completed payload with snapshotJson', () async {
    final plans = [
      PreparationPlan(
        id: 'p1',
        competition: CompetitionSnapshot(
          id: 'c1',
          name: 'X',
          category: '计算机类',
          rulesSummary: const CompetitionRulesSummary(
            signupTime: '',
            contestTime: '',
            teamSize: '',
            format: '',
            organizer: '',
          ),
        ),
        targetDate: DateTime(2026, 8, 15),
        weeklyCommitment: WeeklyCommitment.hours6to10,
        experienceLevel: ExperienceLevel.beginner,
        status: PreparationPlanStatus.active,
        phases: [
          PreparationPhase(
            key: 'p',
            title: '阶段',
            startDate: DateTime(2026, 6, 1),
            endDate: DateTime(2026, 7, 31),
            tasks: [_t('t1')],
          ),
        ],
        createdAt: DateTime(2026, 6, 1),
        updatedAt: DateTime(2026, 6, 1),
      ),
    ];
    final repo = _FakeRepo(plans);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: const PreparationReminderBuilder(),
      activityDays: const {},
      now: () => DateTime(2026, 7, 2, 12),
    );
    final handler = buildNotificationActionHandler(useCase);

    final result = await handler(
      const MethodCall('completeNotificationTask', {
        'planId': 'p1',
        'taskId': 't1',
      }),
    );
    expect(result, isA<Map>());
    expect((result as Map)['status'], 'completed');
    expect(
      (result['snapshotJson'] as String).contains('"schemaVersion":3'),
      isTrue,
    );
  });

  test('handler returns error for missing plan', () async {
    final repo = _FakeRepo([]);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: const PreparationReminderBuilder(),
      activityDays: const {},
      now: () => DateTime(2026, 7, 2, 12),
    );
    final handler = buildNotificationActionHandler(useCase);
    expect(
      () => handler(
        const MethodCall('completeNotificationTask', {
          'planId': 'x',
          'taskId': 'y',
        }),
      ),
      throwsA(isA<PlatformException>()),
    );
  });
}
