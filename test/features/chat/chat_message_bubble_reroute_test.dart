import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/features/chat/widgets/chat_message_bubble.dart';

ChatMessage _reroute() => ChatMessage(
  id: 'r1',
  role: ChatRole.assistant,
  content: '这里咱们专注聊李卫国教授。想看新的导师推荐，回首页重挑一组吧～',
  createdAt: DateTime(2026, 6, 27),
  relatedRecommendations: const [],
  status: ChatMessageStatus.done,
  kind: ChatMessageKind.forkReroute,
);

void main() {
  testWidgets('forkReroute 渲染双选项按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _reroute(),
              onTapRecommendation: (_) {},
              onRerouteHome: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('专注聊'), findsOneWidget);
    expect(find.text('继续问这位'), findsOneWidget);
    expect(find.text('回首页重挑 ›'), findsOneWidget);
  });

  testWidgets('点回首页触发 onRerouteHome', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _reroute(),
              onTapRecommendation: (_) {},
              onRerouteHome: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('回首页重挑 ›'));
    expect(tapped, isTrue);
  });

  testWidgets('forkReroute 已接线 onRegenerate 仍不显示重新生成按钮', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _reroute(),
              onTapRecommendation: (_) {},
              onRegenerate: (_) {},
              onRerouteHome: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('重新生成'), findsNothing);
    expect(find.byTooltip('复制'), findsNothing);
    expect(find.text('继续问这位'), findsOneWidget);
  });
}
