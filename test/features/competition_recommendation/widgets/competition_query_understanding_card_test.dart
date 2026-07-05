// test/features/competition_recommendation/widgets/competition_query_understanding_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/features/competition_recommendation/widgets/competition_query_understanding_card.dart';

void main() {
  testWidgets('渲染 AI 标题 + 键值行 + 待确认', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompetitionQueryUnderstandingCard(
            understanding: CompetitionQueryUnderstanding(
              directions: ['算法'],
              categories: ['计算机类'],
              timingPreferences: ['近期'],
              teamPreferences: ['个人'],
              uncertainties: ['是否需要组队'],
            ),
          ),
        ),
      ),
    );

    expect(find.text('我理解到的需求'), findsOneWidget);
    expect(find.text('算法'), findsOneWidget);
    expect(find.text('计算机类'), findsOneWidget);
    expect(find.text('待确认：'), findsOneWidget);
    expect(find.text('· 是否需要组队'), findsOneWidget);
  });

  testWidgets('兜底隐藏英文技术字段并展示中文待确认项', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompetitionQueryUnderstandingCard(
            understanding: CompetitionQueryUnderstanding(
              directions: ['AI', 'major'],
              categories: ['portfolio'],
              timingPreferences: ['portfolio'],
              teamPreferences: ['team_preference'],
              uncertainties: [
                'major',
                'grade',
                'experience_level',
                'team_preference',
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('portfolio'), findsNothing);
    expect(find.textContaining('major'), findsNothing);
    expect(find.textContaining('experience_level'), findsNothing);
    expect(find.textContaining('team_preference'), findsNothing);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('· 未明确专业'), findsOneWidget);
    expect(find.text('· 未明确年级'), findsOneWidget);
    expect(find.text('· 未明确竞赛经验'), findsOneWidget);
    expect(find.text('· 未明确组队偏好'), findsOneWidget);
  });
}
