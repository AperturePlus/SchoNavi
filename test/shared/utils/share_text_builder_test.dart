import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/preparation_plan.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/shared/utils/share_text_builder.dart';

const _mentor = Recommendation(
  professorId: 'p_1',
  name: '张三',
  university: '清华大学',
  college: '计算机学院',
  title: '教授',
  researchFields: ['人工智能', '机器学习'],
  matchLevel: MatchLevel.high,
  matchScore: 0.86,
  reason: '研究方向高度契合。',
  limitations: [],
  homepageUrl: 'https://example.edu/zhang',
);

const _competition = RecommendedCompetition(
  id: 'c_1',
  name: '挑战杯',
  category: '创新创业',
  level: '国家级',
  tags: ['科研', '团队'],
  teamSize: '3–5 人',
  signupTime: '8 月报名',
  contestTime: '10 月答辩',
  format: '项目制',
  organizer: '共青团中央',
  officialUrl: 'https://example.edu/competition',
  reason: '适合已有项目积累的同学。',
  preparationTips: [],
  limitations: [],
  matchScore: 0.8,
);

PreparationPlan _plan() => PreparationPlan(
  id: 'plan_1',
  competition: CompetitionSnapshot(
    id: 'c_1',
    name: '挑战杯',
    category: '创新创业',
    rulesSummary: const CompetitionRulesSummary(
      signupTime: '',
      contestTime: '',
      teamSize: '',
      format: '',
      organizer: '',
    ),
  ),
  targetDate: DateTime(2026, 9, 1),
  timelineType: CompetitionTimelineType.submission,
  registrationDeadline: DateTime(2026, 8, 1),
  defenseDate: DateTime(2026, 9, 10),
  weeklyCommitment: WeeklyCommitment.hours6to10,
  experienceLevel: ExperienceLevel.beginner,
  status: PreparationPlanStatus.active,
  phases: [
    PreparationPhase(
      key: 'proposal',
      title: '选题与提案',
      startDate: DateTime(2026, 7, 1),
      endDate: DateTime(2026, 8, 15),
      tasks: [
        PreparationTask(
          id: 'done',
          title: '完成选题',
          kind: PreparationTaskKind.required,
          estimatedHours: 3,
          dueDate: DateTime(2026, 7, 10),
          note: '不应导出',
          completedAt: DateTime(2026, 7, 9),
        ),
        PreparationTask(
          id: 'pending',
          title: '撰写提案',
          kind: PreparationTaskKind.required,
          estimatedHours: 8,
          dueDate: DateTime(2026, 8, 15),
          note: '也不应导出',
        ),
      ],
    ),
  ],
  createdAt: DateTime(2026, 7, 1),
  updatedAt: DateTime(2026, 7, 1),
);

void main() {
  test('导师分享文本包含公开信息与核验提示', () {
    final text = ShareTextBuilder.mentor(_mentor);

    expect(text, contains('张三（教授）'));
    expect(text, contains('清华大学 / 计算机学院'));
    expect(text, contains('人工智能、机器学习'));
    expect(text, contains('匹配度：86%'));
    expect(text, contains('https://example.edu/zhang'));
    expect(text, contains('以导师公开信息为准'));
  });

  test('竞赛分享文本包含事实字段与可选官网', () {
    final text = ShareTextBuilder.competition(_competition);

    expect(text, contains('挑战杯'));
    expect(text, contains('创新创业 / 国家级'));
    expect(text, contains('队伍要求：3–5 人'));
    expect(text, contains('赛制：项目制'));
    expect(text, contains('官网：https://example.edu/competition'));
  });

  test('计划分享文本只导出未完成任务，不导出私密备注或内部 ID', () {
    final text = ShareTextBuilder.preparationPlan(_plan());

    expect(text, contains('报名截止：2026-08-01'));
    expect(text, contains('提交截止：2026-09-01'));
    expect(text, contains('答辩日期：2026-09-10'));
    expect(text, contains('每周投入：6–10 小时/周'));
    expect(text, contains('完成进度：1/2'));
    expect(text, contains('撰写提案（截止 2026-08-15，预计 8 小时）'));
    expect(text, isNot(contains('完成选题')));
    expect(text, isNot(contains('不应导出')));
    expect(text, isNot(contains('plan_1')));
    expect(text, isNot(contains('pending')));
  });

  test('AI 回复分享文本不附带用户提问', () {
    final text = ShareTextBuilder.assistantReply('建议先确认导师最新招生信息。');

    expect(text, startsWith('【SchoNavi AI 建议】'));
    expect(text, contains('建议先确认导师最新招生信息。'));
    expect(text, contains('自行核对相关事实'));
  });
}
