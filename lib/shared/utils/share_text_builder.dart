import '../../core/calendar_date.dart';
import '../../domain/entities/preparation_plan.dart';
import '../../domain/entities/recommendation.dart';
import '../../domain/entities/recommended_competition.dart';

class ShareTextBuilder {
  ShareTextBuilder._();

  static String mentor(Recommendation recommendation) {
    final lines = <String>[
      '【SchoNavi 导师推荐】',
      '导师：${recommendation.name}（${recommendation.title}）',
      '单位：${recommendation.university} / ${recommendation.college}',
      if (recommendation.researchFields.isNotEmpty)
        '研究方向：${recommendation.researchFields.join('、')}',
      if (recommendation.matchScore != null)
        '匹配度：${(recommendation.matchScore! * 100).round()}%',
      '推荐理由：${recommendation.reason}',
      if (_hasText(recommendation.homepageUrl)) '主页：${recommendation.homepageUrl}',
      'AI 建议仅供参考，请以导师公开信息为准。',
    ];
    return lines.join('\n');
  }

  static String competition(RecommendedCompetition competition) {
    final lines = <String?>[
      '【SchoNavi 竞赛推荐】',
      '赛事：${competition.name}',
      '类别与级别：${competition.category} / ${competition.level}',
      if (competition.tags.isNotEmpty) '标签：${competition.tags.join('、')}',
      _lineIfText('队伍要求', competition.teamSize),
      _lineIfText('报名信息', competition.signupTime),
      _lineIfText('比赛信息', competition.contestTime),
      _lineIfText('赛制', competition.format),
      _lineIfText('主办方', competition.organizer),
      '推荐理由：${competition.reason}',
      if (_hasText(competition.officialUrl)) '官网：${competition.officialUrl}',
      'AI 建议仅供参考，请以赛事官方通知为准。',
    ].whereType<String>().toList(growable: false);
    return lines.join('\n');
  }

  static String preparationPlan(PreparationPlan plan) {
    final allTasks = plan.phases.expand((phase) => phase.tasks).toList();
    final completedCount = allTasks.where((task) => task.completed).length;
    final targetLabel = plan.timelineType == CompetitionTimelineType.submission
        ? '提交截止'
        : '比赛开始';
    final lines = <String>[
      '【SchoNavi 备赛计划】',
      '赛事：${plan.competition.name}（${plan.competition.category}）',
      if (plan.registrationDeadline != null)
        '报名截止：${CalendarDate.toIsoDay(plan.registrationDeadline!)}',
      '$targetLabel：${CalendarDate.toIsoDay(plan.targetDate)}',
      if (plan.eventEndDate != null)
        '比赛结束：${CalendarDate.toIsoDay(plan.eventEndDate!)}',
      if (plan.defenseDate != null)
        '答辩日期：${CalendarDate.toIsoDay(plan.defenseDate!)}',
      '每周投入：${_weeklyCommitmentLabel(plan.weeklyCommitment)}',
      '计划状态：${_planStatusLabel(plan.status)}',
      '完成进度：$completedCount/${allTasks.length}',
      '',
      '阶段与未完成任务：',
    ];
    for (final phase in plan.phases) {
      lines.add(
        '- ${phase.title}（${CalendarDate.toIsoDay(phase.startDate)} 至 '
        '${CalendarDate.toIsoDay(phase.endDate)}）',
      );
      final pending = phase.tasks.where((task) => !task.completed).toList();
      if (pending.isEmpty) {
        lines.add('  - 已完成');
        continue;
      }
      for (final task in pending) {
        lines.add(
          '  - ${task.title}（截止 ${CalendarDate.toIsoDay(task.dueDate)}，'
          '预计 ${task.estimatedHours} 小时）',
        );
      }
    }
    return lines.join('\n');
  }

  static String assistantReply(String content) =>
      '【SchoNavi AI 建议】\n$content\n\nAI 建议仅供参考，请自行核对相关事实。';

  static String? _lineIfText(String label, String? value) => _hasText(value)
      ? '$label：$value'
      : null;

  static bool _hasText(String? value) => value?.trim().isNotEmpty ?? false;

  static String _weeklyCommitmentLabel(WeeklyCommitment value) => switch (value) {
    WeeklyCommitment.hours3to5 => '3–5 小时/周',
    WeeklyCommitment.hours6to10 => '6–10 小时/周',
    WeeklyCommitment.hours11to15 => '11–15 小时/周',
    WeeklyCommitment.hours16plus => '16 小时以上/周',
  };

  static String _planStatusLabel(PreparationPlanStatus value) => switch (value) {
    PreparationPlanStatus.active => '进行中',
    PreparationPlanStatus.archived => '已归档',
  };
}
