import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/preparation_reminder.dart';
import 'package:scho_navi/domain/services/preparation_reminder_builder.dart';

PreparationPlan plan({
  required String id,
  required DateTime targetDate,
  PreparationPlanStatus status = PreparationPlanStatus.active,
  List<PreparationTask>? tasks,
  List<PreparationPhase>? phases,
}) => PreparationPlan(
  id: id,
  competition: CompetitionSnapshot(
    id: 'c_$id',
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
  targetDate: targetDate,
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.beginner,
  status: status,
  phases:
      phases ??
      [
        PreparationPhase(
          key: 'phase',
          title: '强化训练',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 7, 31),
          tasks: tasks ?? const [],
        ),
      ],
  createdAt: DateTime(2026, 6, 1),
  updatedAt: DateTime(2026, 6, 1),
);

void main() {
  const builder = PreparationReminderBuilder();
  final now = DateTime(2026, 6, 30, 18);

  test('只投影进行中计划并按目标日期和 id 稳定排序', () {
    final snapshot = builder.build(
      plans: [
        plan(id: 'b', targetDate: DateTime(2026, 8, 1)),
        plan(
          id: 'archived',
          targetDate: DateTime(2026, 7, 1),
          status: PreparationPlanStatus.archived,
        ),
        plan(id: 'a', targetDate: DateTime(2026, 8, 1)),
        plan(id: 'early', targetDate: DateTime(2026, 7, 15)),
      ],
      activityDays: const {},
      now: now,
    );

    expect(snapshot.plans.map((item) => item.planId), ['early', 'a', 'b']);
    expect(snapshot.plans.first.currentPhase, '强化训练');
  });

  test('同截止日期优先必做任务并计算进度', () {
    final due = DateTime(2026, 7, 2);
    final snapshot = builder.build(
      plans: [
        plan(
          id: 'p1',
          targetDate: DateTime(2026, 8, 1),
          tasks: [
            PreparationTask(
              id: 'optional',
              title: '可选练习',
              kind: PreparationTaskKind.optional,
              estimatedHours: 1,
              dueDate: due,
            ),
            PreparationTask(
              id: 'required',
              title: '必做练习',
              kind: PreparationTaskKind.required,
              estimatedHours: 1,
              dueDate: due,
            ),
            PreparationTask(
              id: 'done',
              title: '已完成',
              kind: PreparationTaskKind.required,
              estimatedHours: 1,
              dueDate: due,
              completedAt: DateTime(2026, 6, 29),
            ),
          ],
        ),
      ],
      activityDays: const {},
      now: now,
    );

    final summary = snapshot.plans.single;
    expect(summary.nextTaskTitle, '必做练习');
    expect(summary.completedTasks, 1);
    expect(summary.totalTasks, 3);
  });

  test('今天或昨天有活动时延续连续天数，断档归零', () {
    final today = builder.build(
      plans: const [],
      activityDays: const {'2026-06-28', '2026-06-29', '2026-06-30'},
      now: now,
    );
    expect(today.currentStreak, 3);
    expect(today.preparedToday, isTrue);

    final yesterday = builder.build(
      plans: const [],
      activityDays: const {'2026-06-28', '2026-06-29'},
      now: now,
    );
    expect(yesterday.currentStreak, 2);
    expect(yesterday.preparedToday, isFalse);

    final broken = builder.build(
      plans: const [],
      activityDays: const {'2026-06-27', '2026-06-28'},
      now: now,
    );
    expect(broken.currentStreak, 0);
  });

  test('phases 按今天计算 completed/active/upcoming 状态', () {
    final snapshot = builder.build(
      plans: [
        plan(
          id: 'p1',
          targetDate: DateTime(2026, 8, 1),
          phases: [
            PreparationPhase(
              key: 'base',
              title: '基础',
              startDate: DateTime(2026, 6, 1),
              endDate: DateTime(2026, 6, 15),
              tasks: const [],
            ),
            PreparationPhase(
              key: 'sprint',
              title: '冲刺',
              startDate: DateTime(2026, 6, 25),
              endDate: DateTime(2026, 7, 20),
              tasks: const [],
            ),
            PreparationPhase(
              key: 'mock',
              title: '模拟',
              startDate: DateTime(2026, 7, 21),
              endDate: DateTime(2026, 7, 31),
              tasks: const [],
            ),
          ],
        ),
      ],
      activityDays: const {},
      now: now,
    );

    final phases = snapshot.plans.single.phases;
    expect(phases.map((p) => p.title), ['基础', '冲刺', '模拟']);
    expect(phases[0].status, ReminderPhaseStatus.completed);
    expect(phases[1].status, ReminderPhaseStatus.active);
    expect(phases[2].status, ReminderPhaseStatus.upcoming);
  });

  test('phases 超过 5 段时截断为 5 段', () {
    final many = List.generate(
      7,
      (i) => PreparationPhase(
        key: 'p$i',
        title: '阶段$i',
        startDate: DateTime(2026, 6, 1 + i * 5),
        endDate: DateTime(2026, 6, 5 + i * 5),
        tasks: const [],
      ),
    );
    final snapshot = builder.build(
      plans: [plan(id: 'p1', targetDate: DateTime(2026, 8, 1), phases: many)],
      activityDays: const {},
      now: now,
    );
    expect(snapshot.plans.single.phases.length, 5);
  });

  test('PreparationReminderTask round-trips JSON', () {
    final task = PreparationReminderTask(
      taskId: 't1',
      title: '刷题',
      dueIsoDay: '2026-07-02',
      sortOrder: 0,
    );
    final json = task.toJson();
    final back = PreparationReminderTask.fromJson(json);
    expect(back, task);
    expect(json, {
      'taskId': 't1',
      'title': '刷题',
      'dueIsoDay': '2026-07-02',
      'sortOrder': 0,
    });
  });

  test('DeadlineAlert round-trips JSON', () {
    final alert = DeadlineAlert(
      planId: 'p1',
      competitionName: '竞赛 X',
      alertIsoDay: '2026-07-05',
      daysBefore: 7,
      deadlineIsoDay: '2026-07-12',
    );
    final json = alert.toJson();
    final back = DeadlineAlert.fromJson(json);
    expect(back, alert);
    expect(json, {
      'planId': 'p1',
      'competitionName': '竞赛 X',
      'alertIsoDay': '2026-07-05',
      'daysBefore': 7,
      'deadlineIsoDay': '2026-07-12',
    });
  });

  test('Snapshot v3 serializes deadlineAlerts and pendingTasks', () {
    final snapshot = PreparationReminderSnapshot(
      generatedAt: DateTime(2026, 7, 2),
      currentStreak: 1,
      preparedToday: true,
      lastActivityDay: '2026-07-01',
      plans: const [],
      deadlineAlerts: const [
        DeadlineAlert(
          planId: 'p1',
          competitionName: '竞赛 X',
          alertIsoDay: '2026-07-05',
          daysBefore: 7,
          deadlineIsoDay: '2026-07-12',
        ),
      ],
    );
    final json = snapshot.toJson();
    expect(json['schemaVersion'], 3);
    expect((json['deadlineAlerts'] as List).length, 1);
  });

  test(
    'pendingTasks only includes incomplete tasks and sorts by due/kind/order',
    () {
      final due = DateTime(2026, 7, 2);
      final snapshot = builder.build(
        plans: [
          plan(
            id: 'p1',
            targetDate: DateTime(2026, 8, 1),
            tasks: [
              PreparationTask(
                id: 'done',
                title: '已完成',
                kind: PreparationTaskKind.required,
                estimatedHours: 2,
                dueDate: due,
                completedAt: DateTime(2026, 7, 1),
              ),
              PreparationTask(
                id: 'opt',
                title: '可选',
                kind: PreparationTaskKind.optional,
                estimatedHours: 1,
                dueDate: due,
              ),
              PreparationTask(
                id: 'req',
                title: '必做',
                kind: PreparationTaskKind.required,
                estimatedHours: 3,
                dueDate: due,
              ),
            ],
          ),
        ],
        activityDays: const {},
        now: now,
      );
      final tasks = snapshot.plans.first.pendingTasks;
      expect(tasks.map((t) => t.taskId), ['req', 'opt']);
      expect(tasks.first.sortOrder, 0);
      expect(tasks.last.sortOrder, 1);
      expect(snapshot.plans.first.nextTaskTitle, '必做');
    },
  );

  test(
    'deadlineAlerts generate 3 facts per active plan without today filtering',
    () {
      final snapshot = builder.build(
        plans: [plan(id: 'p1', targetDate: DateTime(2026, 8, 15))],
        activityDays: const {},
        now: DateTime(2026, 6, 30),
      );
      final alerts = snapshot.deadlineAlerts;
      expect(alerts.map((a) => a.alertIsoDay).toList(), [
        '2026-08-08', // d-7
        '2026-08-12', // d-3
        '2026-08-15', // d
      ]);
      expect(alerts.first.daysBefore, 7);
      expect(alerts.last.daysBefore, 0);
      expect(alerts.every((a) => a.planId == 'p1'), isTrue);
    },
  );

  test('deadlineAlerts skip archived plans', () {
    final snapshot = builder.build(
      plans: [
        plan(id: 'p1', targetDate: DateTime(2026, 8, 15)),
        plan(
          id: 'arch',
          targetDate: DateTime(2026, 8, 15),
          status: PreparationPlanStatus.archived,
        ),
      ],
      activityDays: const {},
      now: DateTime(2026, 6, 30),
    );
    expect(snapshot.deadlineAlerts.every((a) => a.planId == 'p1'), isTrue);
    expect(snapshot.deadlineAlerts.length, 3);
  });

  test('deadlineAlerts sort by alertIsoDay then planId', () {
    final snapshot = builder.build(
      plans: [
        plan(id: 'b', targetDate: DateTime(2026, 8, 15)),
        plan(id: 'a', targetDate: DateTime(2026, 8, 15)),
      ],
      activityDays: const {},
      now: DateTime(2026, 6, 30),
    );
    // 同 alertIsoDay 下按 planId
    final d7 = snapshot.deadlineAlerts.where((a) => a.daysBefore == 7).toList();
    expect(d7.map((a) => a.planId), ['a', 'b']);
  });
}
