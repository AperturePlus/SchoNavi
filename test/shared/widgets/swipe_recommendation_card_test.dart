import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/shared/widgets/recommendation_card_data.dart';
import 'package:scho_navi/shared/widgets/swipe_recommendation_card.dart';

RecommendationCardData _data(RecommendationKind kind) => RecommendationCardData(
  id: 'x',
  title: '标题',
  subtitle: '副标题',
  tags: const ['标签A', '标签B'],
  matchScore: 0.8,
  reason: '理由理由理由理由理由',
  openUrl: kind == RecommendationKind.competition ? 'https://x' : null,
  kind: kind,
);

void main() {
  testWidgets('导师卡渲染标题/副标题/标签/理由，无官网按钮', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeRecommendationCard(
            data: _data(RecommendationKind.mentor),
            onTap: () {},
          ),
        ),
      ),
    );
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('副标题'), findsOneWidget);
    expect(find.text('标签A'), findsOneWidget);
    expect(find.text('理由理由理由理由理由'), findsOneWidget);
    expect(find.text('访问主页'), findsNothing); // 无 onOpenUrlPressed
  });

  testWidgets('竞赛卡有 onOpenUrlPressed 时显示访问官网', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeRecommendationCard(
            data: _data(RecommendationKind.competition),
            onTap: () {},
            onOpenUrlPressed: () {},
          ),
        ),
      ),
    );
    expect(find.text('访问官网'), findsOneWidget);
  });

  testWidgets('onTap 触发回调', (t) async {
    var tapped = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeRecommendationCard(
            data: _data(RecommendationKind.mentor),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );
    await t.tap(find.text('标题'));
    await t.pump();
    expect(tapped, isTrue);
  });

  testWidgets('长按触发 onLongPress 且不触发 onTap', (t) async {
    var tapped = false;
    var longPressed = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeRecommendationCard(
            data: _data(RecommendationKind.mentor),
            onTap: () => tapped = true,
            onLongPress: () => longPressed = true,
          ),
        ),
      ),
    );
    await t.longPress(find.text('标题'));
    await t.pump();
    expect(longPressed, isTrue);
    expect(tapped, isFalse);
  });

  testWidgets('分享推荐不会触发卡片点击', (t) async {
    var tapped = false;
    var shared = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeRecommendationCard(
            data: _data(RecommendationKind.mentor),
            onTap: () => tapped = true,
            onSharePressed: () async => shared = true,
          ),
        ),
      ),
    );

    expect(find.byTooltip('分享推荐'), findsOneWidget);
    await t.tap(find.byTooltip('分享推荐'));
    await t.pump();
    expect(shared, isTrue);
    expect(tapped, isFalse);
  });
}
