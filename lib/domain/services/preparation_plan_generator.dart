// lib/domain/services/preparation_plan_generator.dart
import '../entities/preparation_plan.dart';
import '../entities/preparation_template.dart';
import '../entities/user_profile.dart';
import '../repositories/preparation_template_provider.dart';
import '../../core/ids/uuid_v7.dart';
import '../../core/result/result.dart';
import '../repositories/preparation_personalizer.dart';
import 'preparation_scheduler.dart';

/// 备赛计划生成器（spec §7.1）：模板 → 经验补基础 → 预算选可选 →
/// 后端个性化合并 → 排期 → 组装 [PreparationPlan]。
///
/// 后端个性化失败时保留后端模板的必做任务。
class PreparationPlanGenerator {
  PreparationPlanGenerator({
    required this.templateProvider,
    required this.personalizer,
    UuidV7? ids,
  }) : _ids = ids ?? UuidV7();

  final PreparationTemplateProvider templateProvider;
  final PreparationPersonalizer personalizer;
  final UuidV7 _ids;

  /// beginner 在组队/选题阶段追加的额外必做任务（spec §7.1 经验补基础）。
  static const _beginnerExtraTasks = <String, List<PreparationTemplateTask>>{
    'team_formation': [
      PreparationTemplateTask(
        templateKey: 'team_intro',
        title: '了解竞赛规则与历届回顾',
        estimatedHours: 2,
      ),
    ],
    'topic_selection': [
      PreparationTemplateTask(
        templateKey: 'topic_brainstorm',
        title: '团队头脑风暴候选选题',
        estimatedHours: 2,
      ),
    ],
  };

  Future<PreparationPlan> generate({
    required CompetitionSnapshot competition,
    required CompetitionTimelineType timelineType,
    required DateTime targetDate,
    DateTime? eventEndDate,
    DateTime? defenseDate,
    required WeeklyCommitment weeklyCommitment,
    required ExperienceLevel experienceLevel,
    required DateTime calendarToday,
    UserProfile? profile,
  }) async {
    // 1. 加载模板：按赛事时间线 + 是否含答辩。
    final template = await templateProvider.load(
      timelineType: timelineType,
      includeDefense: defenseDate != null,
      category: competition.category,
      competitionId: competition.id,
    );

    // 2. 经验补基础：beginner 在指定阶段追加额外必做任务。
    final phases = <PreparationTemplatePhase>[];
    for (final phase in template.phases) {
      var requiredTasks = phase.requiredTasks;
      if (experienceLevel == ExperienceLevel.beginner) {
        final extra = _beginnerExtraTasks[phase.key];
        if (extra != null && extra.isNotEmpty) {
          requiredTasks = [...requiredTasks, ...extra];
        }
      }
      phases.add(
        PreparationTemplatePhase(
          key: phase.key,
          title: phase.title,
          weight: phase.weight,
          requiredTasks: requiredTasks,
          optionalTasks: phase.optionalTasks,
        ),
      );
    }

    // 3. 分段：pre-segment = [calendarToday, targetDate]；
    //    defense-segment = [targetDate+1, defenseDate]（仅当有答辩）。
    final prePhases = phases.where((p) => p.key != 'defense_prep').toList();
    final defensePhases = phases.where((p) => p.key == 'defense_prep').toList();
    final defenseEnd = defenseDate;

    final preSchedule = PreparationScheduler.scheduleSegment(
      phases: prePhases,
      today: calendarToday,
      segmentEnd: targetDate,
    );
    final defenseSchedule = defensePhases.isNotEmpty && defenseEnd != null
        ? PreparationScheduler.scheduleSegment(
            phases: defensePhases,
            today: targetDate.add(const Duration(days: 1)),
            segmentEnd: defenseEnd,
          )
        : const <({String key, DateTime startDate, DateTime endDate})>[];

    // 4. 预算选可选任务：pre 段与 defense 段各自独立预算。
    //    preWeeks = [calendarToday, targetDate] 周数；defenseWeeks = [targetDate,
    //    defenseDate] 周数。
    final hasDefense = defenseEnd != null && defensePhases.isNotEmpty;
    final preDays = targetDate.difference(calendarToday).inDays;
    final preWeeks = preDays <= 0 ? 0.0 : preDays / 7;
    final defenseDays = hasDefense
        ? defenseEnd.difference(targetDate).inDays
        : 0;
    final defenseWeeks = defenseDays <= 0 ? 0.0 : defenseDays / 7;

    final preBudgetHours = weeklyCommitment.hoursPerWeek * preWeeks;
    final defenseBudgetHours = weeklyCommitment.hoursPerWeek * defenseWeeks;

    // 按段内阶段顺序累计可选任务 estimatedHours，超出该段预算则不选。
    final selectedOptionalByPhase = <String, List<PreparationTemplateTask>>{};
    var preUsed = 0.0;
    for (final phase in prePhases) {
      final picked = <PreparationTemplateTask>[];
      for (final task in phase.optionalTasks) {
        if (preUsed + task.estimatedHours > preBudgetHours) continue;
        preUsed += task.estimatedHours;
        picked.add(task);
      }
      selectedOptionalByPhase[phase.key] = picked;
    }
    var defenseUsed = 0.0;
    for (final phase in defensePhases) {
      final picked = <PreparationTemplateTask>[];
      for (final task in phase.optionalTasks) {
        if (defenseUsed + task.estimatedHours > defenseBudgetHours) continue;
        defenseUsed += task.estimatedHours;
        picked.add(task);
      }
      selectedOptionalByPhase[phase.key] = picked;
    }

    // 5. 个性化（成功则合并可选任务 + 写入建议；失败忽略）。
    final personalizationByKey = <String, PreparationPhasePersonalization>{};
    String? globalAdvice;
    final phaseKeys = phases.map((p) => p.key).toList();
    final personalizationResult = await personalizer.personalize(
      req: PreparationPersonalizationRequest(
        competition: competition,
        timelineType: timelineType,
        targetDate: targetDate,
        eventEndDate: eventEndDate,
        defenseDate: defenseDate,
        calendarToday: calendarToday,
        weeklyCommitment: weeklyCommitment,
        experienceLevel: experienceLevel,
        phaseKeys: phaseKeys,
        profile: profile,
      ),
    );
    if (personalizationResult is Success<PreparationPersonalizationResult>) {
      final result = personalizationResult.data;
      globalAdvice = result.globalAdvice;
      for (final ap in result.phases) {
        personalizationByKey[ap.key] = ap;
      }
    }

    // 6. 组装 planPhases：按 template.phases 顺序输出，每阶段从对应段取
    //    startDate/endDate；任务 dueDate = 段 endDate clamp 到该段闭区间。
    //    defense_prep 段任务 clamp 到 [targetDate+1, defenseDate]；
    //    其余阶段 clamp 到 [calendarToday, targetDate]。
    final planPhases = <PreparationPhase>[];
    var taskSeq = 0;
    for (final phase in phases) {
      final isDefense = phase.key == 'defense_prep';
      final schedule = isDefense ? defenseSchedule : preSchedule;
      final seg = _segmentForPhase(phase.key, schedule);
      final defenseStart = targetDate.add(const Duration(days: 1));
      final segLo = isDefense ? defenseStart : calendarToday;
      final segHi = isDefense ? (defenseEnd ?? defenseStart) : targetDate;
      final dueDate = _clamp(seg.endDate, segLo, segHi);

      final tasks = <PreparationTask>[];
      // 必做任务。
      for (final t in phase.requiredTasks) {
        tasks.add(
          PreparationTask(
            id: 'task_${taskSeq++}',
            templateKey: t.templateKey,
            title: t.title,
            kind: PreparationTaskKind.required,
            estimatedHours: t.estimatedHours.round(),
            dueDate: dueDate,
          ),
        );
      }
      // 已选模板可选任务。
      final selectedKeys = <String>{};
      for (final t in selectedOptionalByPhase[phase.key] ?? const []) {
        selectedKeys.add(t.templateKey);
        tasks.add(
          PreparationTask(
            id: 'task_${taskSeq++}',
            templateKey: t.templateKey,
            title: t.title,
            kind: PreparationTaskKind.optional,
            estimatedHours: t.estimatedHours.round(),
            dueDate: dueDate,
          ),
        );
      }
      // 个性化合并的可选任务（去重 templateKey）。
      final phasePersonalization = personalizationByKey[phase.key];
      if (phasePersonalization != null) {
        for (final at in phasePersonalization.optionalTasks) {
          final tk = at.templateKey;
          if (tk != null && selectedKeys.contains(tk)) {
            continue;
          }
          if (tk != null) selectedKeys.add(tk);
          tasks.add(
            PreparationTask(
              id: 'task_${taskSeq++}',
              templateKey: tk,
              title: at.title,
              kind: PreparationTaskKind.optional,
              estimatedHours: at.estimatedHours.round(),
              dueDate: dueDate,
            ),
          );
        }
      }

      planPhases.add(
        PreparationPhase(
          key: phase.key,
          title: phase.title,
          startDate: seg.startDate,
          endDate: seg.endDate,
          tasks: tasks,
          personalizedAdvice: phasePersonalization?.personalizedAdvice,
        ),
      );
    }

    // 7. 警示标志：紧排期仅看 pre 段 [calendarToday, targetDate]；
    //    overload = pre 必做工时超 pre 预算 || defense 必做工时超 defense 预算。
    final tightSchedule = PreparationScheduler.isTightSchedule(
      calendarToday,
      targetDate,
    );
    final overload =
        _computeOverload(prePhases, weeklyCommitment, preWeeks) ||
        (hasDefense &&
            _computeOverload(defensePhases, weeklyCommitment, defenseWeeks));

    // 8. 组装计划。
    return PreparationPlan(
      id: 'pp_${_ids.generate()}',
      competition: competition,
      targetDate: targetDate,
      timelineType: timelineType,
      eventEndDate: eventEndDate,
      defenseDate: defenseDate,
      weeklyCommitment: weeklyCommitment,
      experienceLevel: experienceLevel,
      status: PreparationPlanStatus.active,
      phases: planPhases,
      personalizedSummary: globalAdvice,
      createdAt: calendarToday,
      updatedAt: calendarToday,
      tightSchedule: tightSchedule,
      overload: overload,
      revision: 0,
    );
  }

  /// 段内必做工时是否超过预算（spec §7.1 overload 判定）。
  /// `weeks` 为该段可用周数；预算 = `hoursPerWeek * weeks`。
  bool _computeOverload(
    List<PreparationTemplatePhase> phases,
    WeeklyCommitment weeklyCommitment,
    double weeks,
  ) {
    final requiredHours = phases.fold<double>(
      0,
      (a, p) =>
          a + p.requiredTasks.fold<double>(0, (b, t) => b + t.estimatedHours),
    );
    final budgetHours = weeklyCommitment.hoursPerWeek * weeks;
    return requiredHours > budgetHours;
  }

  /// 找到 phaseKey 所属的排期段：当 schedule 段 key 为合并形如 "a+b" 时，
  /// 含该 phaseKey 的段即为该阶段的段。
  _Segment _segmentForPhase(
    String phaseKey,
    List<({String key, DateTime startDate, DateTime endDate})> schedule,
  ) {
    for (final seg in schedule) {
      if (seg.key == phaseKey || seg.key.split('+').contains(phaseKey)) {
        return _Segment(seg.startDate, seg.endDate);
      }
    }
    // 退化兜底：找不到时用最后一段（不应发生）。
    final last = schedule.last;
    return _Segment(last.startDate, last.endDate);
  }

  DateTime _clamp(DateTime v, DateTime lo, DateTime hi) {
    if (v.isBefore(lo)) return lo;
    if (v.isAfter(hi)) return hi;
    return v;
  }
}

class _Segment {
  const _Segment(this.startDate, this.endDate);
  final DateTime startDate;
  final DateTime endDate;
}
