import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/preparation_reminder.dart';
import 'package:scho_navi/domain/repositories/preparation_plan_repository.dart';
import 'package:scho_navi/domain/services/preparation_reminder_builder.dart';
import 'package:scho_navi/features/preparation/services/complete_notification_task_use_case.dart';

class _FakeRepo implements PreparationPlanRepository {
  _FakeRepo(this._plans);
  List<PreparationPlan> _plans;
  int saveCalls = 0;
  int? forceConflictOnRevision;

  @override
  List<PreparationPlan> list() => _plans;

  @override
  PreparationPlan? findById(String id) {
    for (final p in _plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<PreparationPlan> save(PreparationPlan plan) async {
    saveCalls++;
    if (forceConflictOnRevision != null &&
        plan.revision == forceConflictOnRevision) {
      throw const ConflictException();
    }
    final updated = plan.copyWith(
      revision: plan.revision + 1,
      updatedAt: DateTime(2026, 7, 2),
    );
    _plans = [updated, ..._plans.where((p) => p.id != plan.id)];
    return updated;
  }

  @override
  PreparationPlan? activeForCompetition(String competitionId) => null;
  @override
  Stream<List<PreparationPlan>> watch() => const Stream.empty();
  @override
  Future<void> archive(String id) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<void> clearAll() async {}
}

PreparationTask _task({
  required String id,
  bool completed = false,
  PreparationTaskKind kind = PreparationTaskKind.required,
}) => PreparationTask(
  id: id,
  title: 't$id',
  kind: kind,
  estimatedHours: 1,
  dueDate: DateTime(2026, 7, 2),
  completedAt: completed ? DateTime(2026, 7, 1) : null,
);

PreparationPlan _plan({
  required String id,
  required List<PreparationTask> tasks,
  int revision = 0,
}) => PreparationPlan(
  id: id,
  competition: CompetitionSnapshot(
    id: 'c$id',
    name: '竞赛 $id',
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
  revision: revision,
  phases: [
    PreparationPhase(
      key: 'p',
      title: '阶段',
      startDate: DateTime(2026, 6, 1),
      endDate: DateTime(2026, 7, 31),
      tasks: tasks,
    ),
  ],
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

void main() {
  const builder = PreparationReminderBuilder();
  final now = DateTime(2026, 7, 2, 12);

  test('completes exact taskId and returns v3 snapshot', () async {
    final repo = _FakeRepo([
      _plan(
        id: 'p1',
        tasks: [
          _task(id: 't1'),
          _task(id: 't2'),
        ],
      ),
    ]);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: builder,
      activityDays: const {},
      now: () => now,
    );
    final outcome = await useCase.call(planId: 'p1', taskId: 't1');
    expect(outcome.result, CompleteTaskResult.completed);
    expect(outcome.snapshot, isNotNull);
    expect(PreparationReminderSnapshot.schemaVersion, 3);
    expect(repo.saveCalls, 1);
    final saved = repo.findById('p1')!;
    expect(
      saved.phases.first.tasks.firstWhere((t) => t.id == 't1').completed,
      isTrue,
    );
    expect(
      saved.phases.first.tasks.firstWhere((t) => t.id == 't2').completed,
      isFalse,
    );
  });

  test('already-completed task returns idempotent success', () async {
    final repo = _FakeRepo([
      _plan(
        id: 'p1',
        tasks: [_task(id: 't1', completed: true)],
      ),
    ]);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: builder,
      activityDays: const {},
      now: () => now,
    );
    final outcome = await useCase.call(planId: 'p1', taskId: 't1');
    expect(outcome.result, CompleteTaskResult.alreadyCompleted);
    expect(repo.saveCalls, 0);
    expect(outcome.snapshot, isNotNull);
  });

  test('missing plan returns notFound without saving', () async {
    final repo = _FakeRepo([]);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: builder,
      activityDays: const {},
      now: () => now,
    );
    final outcome = await useCase.call(planId: 'missing', taskId: 't1');
    expect(outcome.result, CompleteTaskResult.notFound);
    expect(repo.saveCalls, 0);
    expect(outcome.snapshot, isNull);
  });

  test('CAS conflict retries once then returns conflict', () async {
    final repo = _FakeRepo([
      _plan(
        id: 'p1',
        revision: 0,
        tasks: [_task(id: 't1')],
      ),
    ]);
    repo.forceConflictOnRevision = 0;
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: builder,
      activityDays: const {},
      now: () => now,
    );
    final outcome = await useCase.call(planId: 'p1', taskId: 't1');
    expect(outcome.result, CompleteTaskResult.conflict);
  });
}
