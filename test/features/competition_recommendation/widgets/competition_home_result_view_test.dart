import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/features/competition_recommendation/providers/competition_home_notifier.dart';
import 'package:scho_navi/features/competition_recommendation/widgets/competition_home_result_view.dart';

CompetitionRecommendationResult _res(int n) => CompetitionRecommendationResult(
  sessionId: 's',
  understanding: CompetitionQueryUnderstanding(
    directions: const ['算法'],
    categories: const ['计算机类'],
    timingPreferences: const [],
    teamPreferences: const [],
    uncertainties: const [],
  ),
  recommendations: List.generate(
    n,
    (i) => RecommendedCompetition(
      id: 'c$i',
      name: '竞赛$i',
      category: '计算机类',
      level: '国家级',
      tags: const ['算法'],
      teamSize: '个人',
      signupTime: '',
      contestTime: '',
      format: '',
      organizer: '',
      officialUrl: 'https://x',
      reason: '契合',
      preparationTips: const [],
      limitations: const [],
      matchScore: 0.7,
    ),
  ),
  followUpQuestions: const [],
);

Widget _wrap(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

CompetitionRecommendationResult _singleWithUrl(String? officialUrl) =>
    CompetitionRecommendationResult(
      sessionId: 's',
      understanding: const CompetitionQueryUnderstanding(
        directions: ['算法'],
        categories: ['计算机类'],
        timingPreferences: [],
        teamPreferences: [],
        uncertainties: [],
      ),
      recommendations: [
        RecommendedCompetition(
          id: 'c0',
          name: '竞赛0',
          category: '计算机类',
          level: '国家级',
          tags: const ['算法'],
          teamSize: '个人',
          signupTime: '',
          contestTime: '',
          format: '',
          organizer: '',
          officialUrl: officialUrl,
          reason: '契合',
          preparationTips: const [],
          limitations: const [],
          matchScore: 0.7,
        ),
      ],
      followUpQuestions: const [],
    );

void main() {
  testWidgets('loading 显示思考占位', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: const CompetitionHomeLoading('我想参加算法竞赛'),
          onAdjust: () {},
          onRetry: (_) async {},
        ),
      ),
    );
    expect(find.text('我想参加算法竞赛'), findsOneWidget); // 用户消息
    expect(find.textContaining('匹配'), findsWidgets); // 思考文案
  });

  testWidgets('result 显示摘要+横滑卡+调整条件', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: CompetitionHomeResult(_res(2)),
          onAdjust: () {},
          onRetry: (_) async {},
        ),
      ),
    );
    expect(find.text('我理解到的需求'), findsOneWidget);
    expect(find.text('竞赛0'), findsOneWidget);
    expect(find.byTooltip('分享推荐'), findsNWidgets(2));
    expect(find.text('调整条件'), findsOneWidget);
  });

  testWidgets('empty 显示调整条件', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: const CompetitionHomeEmpty(),
          onAdjust: () {},
          onRetry: (_) async {},
        ),
      ),
    );
    expect(find.textContaining('暂无'), findsOneWidget);
    expect(find.text('调整条件'), findsOneWidget);
  });

  testWidgets('error 显示重试', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: const CompetitionHomeError('出错了'),
          onAdjust: () {},
          onRetry: (_) async {},
        ),
      ),
    );
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('result 卡片：提供 onOpenUrl 且 openUrl 非空时显示「访问官网」', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: CompetitionHomeResult(_singleWithUrl('https://x')),
          onAdjust: () {},
          onRetry: (_) async {},
          onOpenUrl: (_) {},
        ),
      ),
    );
    expect(find.text('访问官网'), findsOneWidget);
  });

  testWidgets('result 卡片：未提供 onOpenUrl 时不显示「访问官网」', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: CompetitionHomeResult(_singleWithUrl('https://x')),
          onAdjust: () {},
          onRetry: (_) async {},
        ),
      ),
    );
    expect(find.text('访问官网'), findsNothing);
  });

  testWidgets('result 卡片：openUrl 为空时不显示「访问官网」', (t) async {
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: CompetitionHomeResult(_singleWithUrl(null)),
          onAdjust: () {},
          onRetry: (_) async {},
          onOpenUrl: (_) {},
        ),
      ),
    );
    expect(find.text('访问官网'), findsNothing);
  });

  testWidgets('点击卡片触发 onOpenDetail', (t) async {
    var opened = '';
    await t.pumpWidget(
      _wrap(
        CompetitionHomeResultView(
          state: CompetitionHomeResult(_res(1)),
          onAdjust: () {},
          onRetry: (_) async {},
          onOpenDetail: (id) => opened = id,
        ),
      ),
    );
    await t.tap(find.text('竞赛0'));
    await t.pump();
    expect(opened, 'c0');
  });
}
