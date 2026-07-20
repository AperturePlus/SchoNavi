import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/features/competition_recommendation/providers/competition_home_notifier.dart';
import 'package:scho_navi/features/competition_recommendation/widgets/competition_home_result_view.dart';

CompetitionRecommendationResult _denseResult() =>
    CompetitionRecommendationResult(
      sessionId: 's',
      understanding: const CompetitionQueryUnderstanding(
        directions: ['人工智能', '算法与数据结构', '机器学习应用'],
        categories: ['计算机类', '软件类', '数学建模类'],
        timingPreferences: ['今年秋季报名', '明年春季比赛'],
        teamPreferences: ['可组队', '1-3 人'],
        uncertainties: ['不确定自己基础是否够', '不知道报名截止日期是否冲突'],
      ),
      recommendations: List.generate(
        3,
        (i) => RecommendedCompetition(
          id: 'c$i',
          name: '全国大学生程序设计竞赛总决赛 $i',
          category: '计算机类',
          level: '国家级',
          tags: const ['算法', '编程', '团队赛', 'ACM'],
          teamSize: '1-3 人',
          signupTime: '2025-09-01 至 2025-10-15',
          contestTime: '2025-11-15',
          format: '现场赛',
          organizer: '中国计算机学会',
          officialUrl: 'https://example.com/c$i',
          reason: '你的算法基础与该项赛事的侧重方向高度契合，且组队规模符合预期。',
          preparationTips: const [],
          limitations: const [],
          matchScore: 0.85,
        ),
      ),
      followUpQuestions: const ['需要我再推荐一些门槛更低开始备赛吗？'],
    );

void main() {
  testWidgets('result 态在 375x800 / 1.5x 大字体 / 深色主题下无溢出异常', (tester) async {
    addTearDown(() {
      tester.platformDispatcher.clearAllTestValues();
      tester.view.reset();
    });

    // 单一一致的视口设置：375x800 @ 1.0 dpr，1.5x 文本缩放。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(375, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;

    // 与生产布局一致：MaterialApp + Scaffold(body: Column(Expanded(Padding(view))))
    // —— 不额外包裹 SingleChildScrollView，让真实的 RenderFlex 溢出能被捕获。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
                    child: CompetitionHomeResultView(
                      state: CompetitionHomeResult(_denseResult()),
                      prompt:
                          '我想参加一个适合我的算法和人工智能方向的国家级竞赛，'
                          '希望今年秋天报名，可以组队。',
                      onAdjust: () {},
                      onRetry: (_) async {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CompetitionHomeResultView), findsOneWidget);
    expect(find.text('调整条件'), findsOneWidget);
  });
}
