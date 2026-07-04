// test/domain/services/plan_change_validator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/data/dto/plan_change_card_dtos.dart';
import 'package:scho_navi/domain/entities/plan_change_card.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/services/plan_change_validator.dart';

/// 构建一个最小快照用于 validator 测试。
/// `calendarToday` 默认 2026-05-01；targetDate 默认 2026-05-30。
PlanSnapshot _snapshot({
  CompetitionTimelineType timelineType = CompetitionTimelineType.submission,
  DateTime? calendarToday,
  DateTime? targetDate,
  DateTime? defenseDate,
  List<PhaseSnapshot> phases = const [],
}) {
  return PlanSnapshot(
    timelineType: timelineType,
    calendarToday: calendarToday ?? DateTime(2026, 5, 1),
    targetDate: targetDate ?? DateTime(2026, 5, 30),
    defenseDate: defenseDate,
    phases: phases,
  );
}

PhaseSnapshot _phase(
  String key, {
  DateTime? startDate,
  DateTime? endDate,
  List<TaskSnapshot> tasks = const [],
}) => PhaseSnapshot(
  key: key,
  startDate: startDate ?? DateTime(2026, 5, 10),
  endDate: endDate ?? DateTime(2026, 5, 22),
  tasks: tasks,
);

TaskSnapshot _task(
  String id, {
  PreparationTaskKind kind = PreparationTaskKind.required,
  DateTime? dueDate,
  bool completed = false,
}) => TaskSnapshot(
  id: id,
  kind: kind,
  dueDate: dueDate ?? DateTime(2026, 5, 15),
  completed: completed,
);

PlanChangeCard _card({
  String id = 'cc_1',
  required ChangeCardType type,
  String? targetTaskId,
  String? targetPhaseKey,
  DateTime? newDate,
  NewTaskDraft? newTask,
  List<PhaseScheduleDraft>? phaseSchedule,
  String? adviceText,
  String summary = 's',
  String rationale = 'r',
  ChangeCardStatus status = ChangeCardStatus.pending,
  String? rejectionCode,
  String? rejectionReason,
}) => PlanChangeCard(
  id: id,
  type: type,
  targetTaskId: targetTaskId,
  targetPhaseKey: targetPhaseKey,
  newDate: newDate,
  newTask: newTask,
  phaseSchedule: phaseSchedule,
  adviceText: adviceText,
  summary: summary,
  rationale: rationale,
  status: status,
  rejectionCode: rejectionCode,
  rejectionReason: rejectionReason,
);

PlanChangeSet _changeSet(List<PlanChangeCard> cards) =>
    PlanChangeSet(id: 'cs_1', basePlanRevision: 0, cards: cards);

void main() {
  group('max 5 cards', () {
    test('超过 5 张只保留前 5 张', () {
      final cards = List.generate(
        7,
        (i) => _card(
          id: 'cc_$i',
          type: ChangeCardType.appendAdvice,
          adviceText: 'advice $i',
        ),
      );
      final result = PlanChangeValidator.validate(
        _changeSet(cards),
        _snapshot(),
      );
      expect(result, hasLength(5));
      expect(result.first.id, 'cc_0');
      expect(result.last.id, 'cc_4');
    });

    test('恰好 5 张全保留', () {
      final cards = List.generate(
        5,
        (i) => _card(
          id: 'cc_$i',
          type: ChangeCardType.appendAdvice,
          adviceText: 'advice $i',
        ),
      );
      expect(
        PlanChangeValidator.validate(_changeSet(cards), _snapshot()),
        hasLength(5),
      );
    });
  });

  group('target 存在性', () {
    test('服务端 rejected 卡保持原样，不被本地 validator 覆盖', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.appendAdvice,
            targetPhaseKey: 'missing',
            adviceText: '建议',
            status: ChangeCardStatus.rejected,
            rejectionCode: 'invalid_target',
            rejectionReason: '目标阶段不存在',
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'invalid_target');
      expect(result.first.rejectionReason, '目标阶段不存在');
    });

    test('moveTask targetTaskId 不存在 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 'missing',
            newDate: DateTime(2026, 5, 20),
          ),
        ]),
        _snapshot(
          phases: [
            _phase('p1', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'target_task_not_found');
    });

    test('addTask targetPhaseKey 不存在 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'missing',
            newTask: NewTaskDraft(
              title: '新任务',
              estimatedHours: 4,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'target_phase_not_found');
    });

    test('reschedulePhase phaseSchedule 含未知 phaseKey -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'missing',
                startDate: DateTime(2026, 5, 10),
                endDate: DateTime(2026, 5, 20),
              ),
            ],
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'target_phase_not_found');
    });
  });

  group('deleteTask 必做任务保护', () {
    test('必做任务 -> rejected required_task_delete_forbidden', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.deleteTask, targetTaskId: 't_req'),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              tasks: [_task('t_req', kind: PreparationTaskKind.required)],
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'required_task_delete_forbidden');
    });

    test('optional 任务可删除 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.deleteTask, targetTaskId: 't_opt'),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              tasks: [_task('t_opt', kind: PreparationTaskKind.optional)],
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('userAdded 任务可删除 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.deleteTask, targetTaskId: 't_user'),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              tasks: [_task('t_user', kind: PreparationTaskKind.userAdded)],
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('已完成任务不可删除 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.deleteTask, targetTaskId: 't_done'),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              tasks: [
                _task(
                  't_done',
                  kind: PreparationTaskKind.optional,
                  completed: true,
                ),
              ],
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'completed_task_protected');
    });
  });

  group('addTask 字段校验', () {
    test('标题为空 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'p1',
            newTask: NewTaskDraft(
              title: '  ',
              estimatedHours: 4,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'invalid_add_task_fields');
    });

    test('estimatedHours=0 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'p1',
            newTask: NewTaskDraft(
              title: '新任务',
              estimatedHours: 0,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'invalid_add_task_fields');
    });

    test('estimatedHours=201 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'p1',
            newTask: NewTaskDraft(
              title: '新任务',
              estimatedHours: 201,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'invalid_add_task_fields');
    });

    test('estimatedHours=1 合法 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'p1',
            newTask: NewTaskDraft(
              title: '新任务',
              estimatedHours: 1,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('estimatedHours=200 合法 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.addTask,
            targetPhaseKey: 'p1',
            newTask: NewTaskDraft(
              title: '新任务',
              estimatedHours: 200,
              dueDate: DateTime(2026, 5, 20),
            ),
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });
  });

  group('窗口型日期范围 [calendarToday, targetDate]', () {
    test('moveTask newDate 在范围内 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 5, 20),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.eventWindow,
          phases: [
            _phase('p1', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('moveTask newDate 晚于 targetDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 6, 1),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.eventWindow,
          phases: [
            _phase('p1', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });

    test('moveTask newDate 早于 calendarToday -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 4, 30),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.eventWindow,
          phases: [
            _phase('p1', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });
  });

  group('提交型日期范围', () {
    test('非 defense_prep 任务晚于 targetDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 6, 1),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.submission,
          phases: [
            _phase('proposal_writing', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });

    test('defense_prep 任务在 [targetDate+1, defenseDate] -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 6, 5),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.submission,
          defenseDate: DateTime(2026, 6, 10),
          phases: [
            _phase('defense_prep', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('defense_prep 任务早于 targetDate+1 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 5, 30),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.submission,
          defenseDate: DateTime(2026, 6, 10),
          phases: [
            _phase('defense_prep', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });

    test('defense_prep 任务晚于 defenseDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 6, 11),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.submission,
          defenseDate: DateTime(2026, 6, 10),
          phases: [
            _phase('defense_prep', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });

    test('无 defenseDate 时 defense_prep 任务非法 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't1',
            newDate: DateTime(2026, 5, 20),
          ),
        ]),
        _snapshot(
          timelineType: CompetitionTimelineType.submission,
          defenseDate: null,
          phases: [
            _phase('defense_prep', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'date_out_of_range');
    });
  });

  group('已完成任务保护', () {
    test('已完成任务不可移动 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.moveTask,
            targetTaskId: 't_done',
            newDate: DateTime(2026, 5, 20),
          ),
        ]),
        _snapshot(
          phases: [
            _phase('p1', tasks: [_task('t_done', completed: true)]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'completed_task_protected');
    });
  });

  group('reschedulePhase 合并重叠检查', () {
    test('单阶段合法重设 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 5),
                endDate: DateTime(2026, 5, 25),
              ),
            ],
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('阶段 endDate 晚于 targetDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 5),
                endDate: DateTime(2026, 6, 5),
              ),
            ],
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'phase_schedule_invalid');
    });

    test('与未列出的相邻阶段重叠 -> 整张拒绝', () {
      // p1: 5/10-5/22, p2: 5/23-5/28
      // 卡只重设 p1 为 5/15-5/25，与 p2(5/23) 重叠
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 15),
                endDate: DateTime(2026, 5, 25),
              ),
            ],
          ),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              startDate: DateTime(2026, 5, 10),
              endDate: DateTime(2026, 5, 22),
            ),
            _phase(
              'p2',
              startDate: DateTime(2026, 5, 23),
              endDate: DateTime(2026, 5, 28),
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'phase_schedule_invalid');
    });

    test('阶段顺序反转（开始晚于下一阶段开始）-> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 26),
                endDate: DateTime(2026, 5, 28),
              ),
            ],
          ),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              startDate: DateTime(2026, 5, 10),
              endDate: DateTime(2026, 5, 22),
            ),
            _phase(
              'p2',
              startDate: DateTime(2026, 5, 23),
              endDate: DateTime(2026, 5, 28),
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'phase_schedule_invalid');
    });

    test('阶段可留空档但不重叠 -> pending', () {
      // p1 重设为 5/5-5/15，p2 保持 5/23-5/28，中间 5/16-5/22 空档
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 5),
                endDate: DateTime(2026, 5, 15),
              ),
            ],
          ),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              startDate: DateTime(2026, 5, 10),
              endDate: DateTime(2026, 5, 22),
            ),
            _phase(
              'p2',
              startDate: DateTime(2026, 5, 23),
              endDate: DateTime(2026, 5, 28),
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('草稿自身 startDate 晚于 endDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 25),
                endDate: DateTime(2026, 5, 15),
              ),
            ],
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'phase_schedule_invalid');
    });

    test('相邻阶段相接（start == prevEnd）-> rejected（闭区间共享同日=重叠）', () {
      // 阶段 A 重设为 5/5–5/22，阶段 B 保持 5/22–5/28（B.start == A.end）。
      // 日期为闭区间，5/22 同属两个阶段，视为重叠，应拒绝。
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 5),
                endDate: DateTime(2026, 5, 22),
              ),
            ],
          ),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              startDate: DateTime(2026, 5, 10),
              endDate: DateTime(2026, 5, 22),
            ),
            _phase(
              'p2',
              startDate: DateTime(2026, 5, 22),
              endDate: DateTime(2026, 5, 28),
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'phase_schedule_invalid');
    });

    test('相邻阶段无空档邻接（start == prevEnd+1）-> pending', () {
      // 阶段 A 重设为 5/5–5/22，阶段 B 保持 5/23–5/28（B.start == A.end+1）。
      // 这是 scheduler 自身输出模式（cursor = endDate + 1 day），应通过。
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.reschedulePhase,
            phaseSchedule: [
              PhaseScheduleDraft(
                phaseKey: 'p1',
                startDate: DateTime(2026, 5, 5),
                endDate: DateTime(2026, 5, 22),
              ),
            ],
          ),
        ]),
        _snapshot(
          phases: [
            _phase(
              'p1',
              startDate: DateTime(2026, 5, 10),
              endDate: DateTime(2026, 5, 22),
            ),
            _phase(
              'p2',
              startDate: DateTime(2026, 5, 23),
              endDate: DateTime(2026, 5, 28),
            ),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });
  });

  group('appendAdvice', () {
    test('有 targetPhaseKey 且存在 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.appendAdvice,
            targetPhaseKey: 'p1',
            adviceText: '建议',
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('无 targetPhaseKey 全局建议 -> pending', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.appendAdvice, adviceText: '全局建议'),
        ]),
        _snapshot(),
      );
      expect(result.first.status, ChangeCardStatus.pending);
    });

    test('adviceText 为空 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(type: ChangeCardType.appendAdvice, adviceText: '  '),
        ]),
        _snapshot(),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'invalid_advice_fields');
    });

    test('有 targetPhaseKey 但不存在 -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([
          _card(
            type: ChangeCardType.appendAdvice,
            targetPhaseKey: 'missing',
            adviceText: '建议',
          ),
        ]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'target_phase_not_found');
    });
  });

  group('必填字段缺失', () {
    test('moveTask 缺 newDate -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([_card(type: ChangeCardType.moveTask, targetTaskId: 't1')]),
        _snapshot(
          phases: [
            _phase('p1', tasks: [_task('t1')]),
          ],
        ),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'missing_required_fields');
    });

    test('addTask 缺 newTask -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([_card(type: ChangeCardType.addTask, targetPhaseKey: 'p1')]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'missing_required_fields');
    });

    test('reschedulePhase 缺 phaseSchedule -> rejected', () {
      final result = PlanChangeValidator.validate(
        _changeSet([_card(type: ChangeCardType.reschedulePhase)]),
        _snapshot(phases: [_phase('p1')]),
      );
      expect(result.first.status, ChangeCardStatus.rejected);
      expect(result.first.rejectionCode, 'missing_required_fields');
    });
  });

  group('JSON 往返', () {
    test('PlanChangeSet toJson/fromJson 往返保持字段', () {
      final original = PlanChangeSet(
        id: 'cs_x',
        basePlanRevision: 3,
        cards: [
          PlanChangeCard(
            id: 'cc_1',
            type: ChangeCardType.addTask,
            targetPhaseKey: 'defense_prep',
            newTask: NewTaskDraft(
              title: '模拟答辩',
              estimatedHours: 3,
              dueDate: DateTime(2026, 6, 5),
              note: '记录追问',
            ),
            summary: '新增模拟答辩',
            rationale: '答辩前复盘',
          ),
          PlanChangeCard(
            id: 'cc_2',
            type: ChangeCardType.deleteTask,
            targetTaskId: 't_old',
            summary: '删除旧任务',
            rationale: '不再需要',
            status: ChangeCardStatus.rejected,
            rejectionCode: 'required_task_delete_forbidden',
            rejectionReason: '必做任务不可删除',
          ),
        ],
      );
      final round = PlanChangeSet.fromJson(original.toJson());
      expect(round.id, 'cs_x');
      expect(round.basePlanRevision, 3);
      expect(round.cards, hasLength(2));
      expect(round.cards[0].type, ChangeCardType.addTask);
      expect(round.cards[0].newTask!.title, '模拟答辩');
      expect(round.cards[0].newTask!.dueDate, DateTime(2026, 6, 5));
      expect(round.cards[1].type, ChangeCardType.deleteTask);
      expect(round.cards[1].status, ChangeCardStatus.rejected);
      expect(round.cards[1].rejectionCode, 'required_task_delete_forbidden');
    });

    test('wire 枚举值为 snake_case', () {
      final card = PlanChangeCard(
        id: 'c',
        type: ChangeCardType.reschedulePhase,
        summary: '',
        rationale: '',
      );
      final json = card.toJson();
      expect(json['type'], 'reschedule_phase');
      expect(json['status'], 'pending');
    });
  });

  group('PlanChangeSetDto', () {
    test('完整 LLM 输出解码为 PlanChangeSet（保留 wire status，缺省 pending）', () {
      final json = <String, dynamic>{
        'reply': '我整理了两项调整。',
        'change_set': {
          'id': 'cs_1',
          'base_plan_revision': 3,
          'cards': [
            {
              'id': 'cc_1',
              'type': 'move_task',
              'target_task_id': 'task_core_algo',
              'new_date': '2026-05-22',
              'summary': '移动核心算法',
              'rationale': '避开期末考试',
              'status': 'applied',
            },
            {
              'id': 'cc_2',
              'type': 'add_task',
              'target_phase_key': 'defense_prep',
              'new_task': {
                'title': '第二次模拟答辩',
                'estimated_hours': 3,
                'due_date': '2026-06-05',
                'note': '记录追问',
              },
              'summary': '新增模拟答辩',
              'rationale': '答辩前复盘',
            },
          ],
        },
      };
      final dto = PlanChangeSetDto.fromJson(json);
      expect(dto.reply, '我整理了两项调整。');
      expect(dto.changeSet.id, 'cs_1');
      expect(dto.changeSet.basePlanRevision, 3);
      expect(dto.changeSet.cards, hasLength(2));
      expect(dto.changeSet.cards[0].status, ChangeCardStatus.applied);
      expect(dto.changeSet.cards[0].type, ChangeCardType.moveTask);
      expect(dto.changeSet.cards[0].targetTaskId, 'task_core_algo');
      expect(dto.changeSet.cards[0].newDate, DateTime(2026, 5, 22));
      expect(dto.changeSet.cards[1].type, ChangeCardType.addTask);
      expect(dto.changeSet.cards[1].status, ChangeCardStatus.pending);
      expect(dto.changeSet.cards[1].newTask!.estimatedHours, 3);
      expect(dto.changeSet.cards[1].newTask!.dueDate, DateTime(2026, 6, 5));
    });

    test('后端 rejected 状态与拒绝原因会被保留', () {
      final dto = PlanChangeSetDto.fromJson({
        'reply': '调整',
        'change_set': {
          'id': 'cs_rej',
          'base_plan_revision': 0,
          'cards': [
            {
              'id': 'cc_rej',
              'type': 'append_advice',
              'target_phase_key': 'missing',
              'advice_text': '建议',
              'summary': '追加建议',
              'rationale': '阶段不存在',
              'status': 'rejected',
              'rejection_code': 'invalid_target',
              'rejection_reason': '目标阶段不存在',
            },
          ],
        },
      });
      final card = dto.changeSet.cards.first;
      expect(card.status, ChangeCardStatus.rejected);
      expect(card.rejectionCode, 'invalid_target');
      expect(card.rejectionReason, '目标阶段不存在');
    });

    test('rejectionCode/rejectionReason camelCase 字段可解码', () {
      final dto = PlanChangeSetDto.fromJson({
        'reply': '调整',
        'change_set': {
          'id': 'cs_rej',
          'base_plan_revision': 0,
          'cards': [
            {
              'id': 'cc_rej',
              'type': 'append_advice',
              'summary': '追加建议',
              'rationale': '阶段不存在',
              'status': 'rejected',
              'rejectionCode': 'invalid_target',
              'rejectionReason': '目标阶段不存在',
            },
          ],
        },
      });
      final card = dto.changeSet.cards.first;
      expect(card.status, ChangeCardStatus.rejected);
      expect(card.rejectionCode, 'invalid_target');
      expect(card.rejectionReason, '目标阶段不存在');
    });

    test('DTO 解码后可直接送 validator 校验', () {
      final json = <String, dynamic>{
        'reply': '调整',
        'change_set': {
          'id': 'cs_2',
          'base_plan_revision': 0,
          'cards': [
            {
              'id': 'cc_1',
              'type': 'delete_task',
              'target_task_id': 't_req',
              'summary': '删必做',
              'rationale': '不该删',
            },
          ],
        },
      };
      final dto = PlanChangeSetDto.fromJson(json);
      final snapshot = _snapshot(
        phases: [
          _phase(
            'p1',
            tasks: [_task('t_req', kind: PreparationTaskKind.required)],
          ),
        ],
      );
      final validated = PlanChangeValidator.validate(dto.changeSet, snapshot);
      expect(validated.first.status, ChangeCardStatus.rejected);
      expect(validated.first.rejectionCode, 'required_task_delete_forbidden');
    });

    test('change_set 缺失抛 FormatException', () {
      expect(
        () => PlanChangeSetDto.fromJson({'reply': 'x'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('未知 type 抛 FormatException', () {
      expect(
        () => PlanChangeSetDto.fromJson({
          'reply': 'x',
          'change_set': {
            'id': 'cs_1',
            'base_plan_revision': 0,
            'cards': [
              {'id': 'c1', 'type': 'bogus', 'summary': '', 'rationale': ''},
            ],
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('new_task.due_date 非法格式抛 FormatException', () {
      expect(
        () => PlanChangeSetDto.fromJson({
          'reply': 'x',
          'change_set': {
            'id': 'cs_1',
            'base_plan_revision': 0,
            'cards': [
              {
                'id': 'c1',
                'type': 'add_task',
                'target_phase_key': 'p1',
                'new_task': {
                  'title': 't',
                  'estimated_hours': 4,
                  'due_date': '2026/06/05',
                },
                'summary': '',
                'rationale': '',
              },
            ],
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('new_task.estimated_hours 非整数抛 FormatException（不静默截断）', () {
      // spec §3.5：estimatedHours 1–200 整数。4.5 不应被截为 4 后通过校验。
      expect(
        () => PlanChangeSetDto.fromJson({
          'reply': 'x',
          'change_set': {
            'id': 'cs_1',
            'base_plan_revision': 0,
            'cards': [
              {
                'id': 'c1',
                'type': 'add_task',
                'target_phase_key': 'p1',
                'new_task': {
                  'title': 't',
                  'estimated_hours': 4.5,
                  'due_date': '2026-06-05',
                },
                'summary': '',
                'rationale': '',
              },
            ],
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('new_task.estimated_hours 整数（如 4.0）合法解码', () {
      // 4.0 数值上等于整数，不应被拒。
      final dto = PlanChangeSetDto.fromJson({
        'reply': 'x',
        'change_set': {
          'id': 'cs_1',
          'base_plan_revision': 0,
          'cards': [
            {
              'id': 'c1',
              'type': 'add_task',
              'target_phase_key': 'p1',
              'new_task': {
                'title': 't',
                'estimated_hours': 4.0,
                'due_date': '2026-06-05',
              },
              'summary': '',
              'rationale': '',
            },
          ],
        },
      });
      expect(dto.changeSet.cards.first.newTask!.estimatedHours, 4);
    });

    test('toJson/fromJson 往返保持 reply 与 changeSet', () {
      final original = PlanChangeSetDto(
        reply: '回复',
        changeSet: PlanChangeSet(
          id: 'cs_r',
          basePlanRevision: 1,
          cards: [
            PlanChangeCard(
              id: 'c1',
              type: ChangeCardType.appendAdvice,
              adviceText: '建议',
              summary: 's',
              rationale: 'r',
            ),
          ],
        ),
      );
      final round = PlanChangeSetDto.fromJson(original.toJson());
      expect(round.reply, '回复');
      expect(round.changeSet.id, 'cs_r');
      expect(round.changeSet.cards.first.type, ChangeCardType.appendAdvice);
    });
  });
}
