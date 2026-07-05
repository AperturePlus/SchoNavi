import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/features/competition_recommendation/widgets/competition_ai_tips_block.dart';

const _base = RecommendedCompetition(
  id: 'c',
  name: 'C',
  category: '计算机类',
  level: '国家级',
  tags: [],
  teamSize: '',
  signupTime: '',
  contestTime: '',
  format: '',
  organizer: '',
  officialUrl: null,
  reason: '',
  preparationTips: [],
  limitations: [],
  matchScore: 0,
);

void main() {
  testWidgets('两列表空时不渲染', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionAiTipsBlock(competition: _base)),
      ),
    );
    expect(find.text('AI 补充提示'), findsNothing);
  });

  testWidgets('有 limitations 和 tips 时渲染', (t) async {
    final c = _base.copyWith(
      preparationTips: const ['刷真题', '组队训练'],
      limitations: const ['以官网为准'],
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionAiTipsBlock(competition: c)),
      ),
    );
    expect(find.text('AI 补充提示'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNWidgets(3));
    expect(find.text('· 刷真题'), findsOneWidget);
    expect(find.text('· 以官网为准'), findsOneWidget);
  });

  testWidgets('tips 和 limitations 支持 Markdown', (t) async {
    final c = _base.copyWith(
      preparationTips: const ['**重点**：先读规则'],
      limitations: const ['**注意**：以官网为准'],
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompetitionAiTipsBlock(competition: c)),
      ),
    );

    expect(find.byType(GptMarkdown), findsNWidgets(2));
    expect(find.text('· **重点**：先读规则'), findsNothing);
    expect(find.text('· **注意**：以官网为准'), findsNothing);
  });
}
