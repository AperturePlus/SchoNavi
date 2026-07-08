import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/features/competition_recommendation/widgets/competition_fact_block.dart';

RecommendedCompetition _c() => const RecommendedCompetition(
  id: 'c',
  name: 'C',
  category: '计算机类',
  level: '国家级',
  tags: [],
  teamSize: '3 人团队',
  signupTime: '约每年 4 月',
  contestTime: '9-12 月',
  format: '5 小时编程',
  organizer: 'ACM',
  officialUrl: 'https://x',
  reason: '',
  preparationTips: [],
  limitations: [],
  matchScore: 0,
);

void main() {
  testWidgets('渲染目录事实键值', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionFactBlock(competition: _c())),
      ),
    );
    expect(find.text('报名时间'), findsOneWidget);
    expect(find.text('约每年 4 月'), findsOneWidget);
    expect(find.text('比赛时间'), findsOneWidget);
    expect(find.text('9-12 月'), findsOneWidget);
    expect(find.text('团队规模'), findsOneWidget);
    expect(find.text('3 人团队'), findsOneWidget);
    expect(find.text('形式'), findsOneWidget);
    expect(find.text('5 小时编程'), findsOneWidget);
    expect(find.text('主办方'), findsOneWidget);
    expect(find.text('ACM'), findsOneWidget);
  });

  testWidgets('空值显示暂无信息', (t) async {
    final c = _c().copyWith(signupTime: '', teamSize: '');
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionFactBlock(competition: c)),
      ),
    );
    expect(find.text('暂无信息'), findsNWidgets(2));
  });

  testWidgets('事实字段支持 Markdown 渲染', (t) async {
    final c = _c().copyWith(
      signupTime: '**名称纠错**：赛事现称 ICPC',
      contestTime: '**路径**：校内选拔、区域赛和 World Finals',
      format: '**形式**：3 人组队限时编程',
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionFactBlock(competition: c)),
      ),
    );

    expect(find.byType(GptMarkdown), findsNWidgets(5));
    expect(find.text('**名称纠错**：赛事现称 ICPC'), findsNothing);
    expect(find.text('**形式**：3 人组队限时编程'), findsNothing);
  });
}
