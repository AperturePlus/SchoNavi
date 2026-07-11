import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/favorite_item.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/domain/repositories/favorite_repository.dart';
import 'package:scho_navi/features/chat/widgets/chat_message_bubble.dart';
import 'package:scho_navi/features/chat/widgets/inline_dislike_feedback.dart';
import 'package:scho_navi/shared/widgets/swipe_recommendation_card.dart';
import 'package:scho_navi/shared/widgets/thinking_indicator.dart';

const _rec = Recommendation(
  professorId: 'p_001',
  name: '张三',
  university: '上海交通大学',
  college: '电子信息与电气工程学院',
  title: '教授',
  researchFields: ['医学影像', '计算机视觉'],
  matchLevel: MatchLevel.high,
  reason: '方向相关。',
  limitations: [],
);

class _FakeFavoriteRepo implements FavoriteRepository {
  final _items = <String, FavoriteItem>{};
  final _controller = StreamController<List<FavoriteItem>>.broadcast();
  @override
  List<FavoriteItem> list() => _items.values.toList();
  @override
  Stream<List<FavoriteItem>> watch() => _controller.stream;
  @override
  bool isFavorite(String professorId) => _items.containsKey(professorId);
  @override
  Future<void> add(FavoriteItem item) async {
    _items[item.professorId] = item;
    _controller.add(list());
  }

  @override
  Future<void> remove(String professorId) async {
    _items.remove(professorId);
    _controller.add(list());
  }

  @override
  Future<bool> toggle(FavoriteItem item) async {
    if (_items.containsKey(item.professorId)) {
      await remove(item.professorId);
      return false;
    }
    await add(item);
    return true;
  }
}

ChatMessage _msg({
  required ChatRole role,
  required String content,
  required ChatMessageStatus status,
  ChatMessageKind kind = ChatMessageKind.conversation,
  List<Recommendation> related = const [],
}) => ChatMessage(
  id: 'm_0',
  role: role,
  content: content,
  createdAt: DateTime(2026, 6, 9),
  relatedRecommendations: related,
  status: status,
  kind: kind,
);

Future<void> _pump(
  WidgetTester tester,
  ChatMessage message, {
  void Function(String)? onTap,
  void Function(String)? onRetryRecommendation,
  void Function(String)? onRetry,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ChatMessageBubble(
            message: message,
            onTapRecommendation: onTap ?? (_) {},
            onRetryRecommendation: onRetryRecommendation,
            onRegenerate: onRetry == null ? null : (id) => onRetry(id),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('用户消息用纯文本、无 Markdown', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.user,
        content: '为什么推荐他',
        status: ChatMessageStatus.done,
      ),
    );

    expect(find.text('为什么推荐他'), findsOneWidget);
    expect(find.byType(GptMarkdown), findsNothing);
  });

  testWidgets('助手消息用 Markdown 渲染', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '**加粗** 回答',
        status: ChatMessageStatus.done,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GptMarkdown), findsOneWidget);
  });

  testWidgets('思考中显示进度指示与文案', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.sending,
      ),
    );

    expect(find.byType(ThinkingIndicator), findsOneWidget);
    expect(find.text('正在思考'), findsOneWidget);
  });

  testWidgets('助手错误态显示圆圈红感叹号与查看详情', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '服务异常，请稍后重试',
        status: ChatMessageStatus.error,
      ),
    );
    await tester.pumpAndSettle();

    // 圆圈红感叹号图标
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // 默认折叠，不直接展示错误文案
    expect(find.text('服务异常，请稍后重试'), findsNothing);
    // 「查看详情」按钮存在
    expect(find.text('查看详情'), findsOneWidget);
  });

  testWidgets('点击查看详情展开错误文案', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '服务异常，请稍后重试',
        status: ChatMessageStatus.error,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text('服务异常，请稍后重试'), findsOneWidget);
  });

  testWidgets('错误态有重试按钮回调', (tester) async {
    String? retried;
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '服务异常，请稍后重试',
        status: ChatMessageStatus.error,
      ),
      onRetry: (_) => retried = 'm_0',
    );
    await tester.pumpAndSettle();

    expect(find.text('重试'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(retried, 'm_0');
  });

  testWidgets('嵌入推荐卡片可点击回调', (tester) async {
    String? tapped;
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '相近导师如下',
        status: ChatMessageStatus.done,
        related: const [_rec],
      ),
      onTap: (id) => tapped = id,
    );
    await tester.pumpAndSettle();

    expect(find.byType(SwipeRecommendationCard), findsOneWidget);
    await tester.tap(find.byType(SwipeRecommendationCard));
    expect(tapped, 'p_001');
  });

  testWidgets('流式中（有文本）显示 Markdown 与生成中指示', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '正在生成的**部分**',
        status: ChatMessageStatus.streaming,
      ),
    );

    expect(find.byType(GptMarkdown), findsOneWidget);
    expect(find.text('生成中…'), findsOneWidget);
  });

  testWidgets('流式中（空文本）显示正在思考', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '',
        status: ChatMessageStatus.streaming,
      ),
    );

    expect(find.byType(ThinkingIndicator), findsOneWidget);
    expect(find.text('正在思考'), findsOneWidget);
  });

  testWidgets('推荐失败显示重试按钮且不显示重新生成操作', (tester) async {
    String? retried;
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '服务异常，请稍后重试',
        status: ChatMessageStatus.error,
        kind: ChatMessageKind.recommendation,
      ),
      onRetryRecommendation: (id) => retried = id,
    );

    expect(find.text('重试推荐'), findsOneWidget);
    expect(find.byTooltip('重新生成'), findsNothing);
    await tester.tap(find.text('重试推荐'));
    expect(retried, 'm_0');
  });

  testWidgets('助手正常回复无气泡容器(全宽透明)', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '这是一段较长的助手回复，应当全宽显示而不被气泡收窄',
        status: ChatMessageStatus.done,
      ),
    );
    await tester.pumpAndSettle();

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration);
    final bubbleContainers = containers.where((c) {
      final box = c.decoration as BoxDecoration;
      return box.color != null && box.borderRadius != null;
    });
    expect(bubbleContainers, isEmpty, reason: '助手回复不应有带背景色的圆角气泡');
    expect(find.byType(GptMarkdown), findsOneWidget);
  });

  testWidgets('用户消息仍保留气泡', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.user,
        content: '用户消息',
        status: ChatMessageStatus.done,
      ),
    );
    await tester.pumpAndSettle();

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration);
    final bubble = containers.where((c) {
      final box = c.decoration as BoxDecoration;
      return box.color != null && box.borderRadius != null;
    });
    expect(bubble, isNotEmpty, reason: '用户消息应保留气泡');
  });

  testWidgets('助手回复行高常量可读取且大于0', (tester) async {
    expect(ChatMessageBubble.assistantLineHeight, greaterThan(0));
  });

  testWidgets('推荐卡片 done 态展示统一动作条（复制/赞/踩）无孤立感叹号', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _msg(
                role: ChatRole.assistant,
                content: '推荐如下',
                status: ChatMessageStatus.done,
                kind: ChatMessageKind.recommendation,
              ),
              onTapRecommendation: (_) {},
              onFeedback: (_, _) {},
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byTooltip('分享'), findsOneWidget);
    expect(find.byTooltip('有用'), findsOneWidget);
    expect(find.byTooltip('没用'), findsOneWidget);
    expect(find.byTooltip('反馈这条推荐'), findsNothing);
  });

  testWidgets('未完成或非助手消息不显示分享', (tester) async {
    await _pump(
      tester,
      _msg(
        role: ChatRole.user,
        content: '用户消息',
        status: ChatMessageStatus.done,
      ),
    );
    expect(find.byTooltip('分享'), findsNothing);

    await _pump(
      tester,
      _msg(
        role: ChatRole.assistant,
        content: '生成中内容',
        status: ChatMessageStatus.streaming,
      ),
    );
    expect(find.byTooltip('分享'), findsNothing);
  });

  testWidgets('点踩展开内联输入框并提交调 onDislikeFeedback', (tester) async {
    String? dislikedId;
    String? dislikedContent;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _msg(
                role: ChatRole.assistant,
                content: '推荐如下',
                status: ChatMessageStatus.done,
              ),
              onTapRecommendation: (_) {},
              onFeedback: (_, _) {},
              onDislikeFeedback: (id, content) {
                dislikedId = id;
                dislikedContent = content;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('没用'));
    await tester.pump();
    expect(find.byType(InlineDislikeFeedback), findsOneWidget);
    await tester.enterText(find.byType(InlineDislikeFeedback), '推荐得不对');
    await tester.tap(find.text('提交'));
    expect(dislikedId, 'm_0');
    expect(dislikedContent, '推荐得不对');
  });

  testWidgets('赞调 onFeedback 置 like', (tester) async {
    String? fbId;
    ChatMessageFeedback? fb;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _msg(
                role: ChatRole.assistant,
                content: '好的',
                status: ChatMessageStatus.done,
              ),
              onTapRecommendation: (_) {},
              onFeedback: (id, f) {
                fbId = id;
                fb = f;
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('有用'));
    expect(fbId, 'm_0');
    expect(fb, ChatMessageFeedback.like);
  });

  testWidgets('再次点踩收起内联输入框', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _msg(
                role: ChatRole.assistant,
                content: '推荐如下',
                status: ChatMessageStatus.done,
              ),
              onTapRecommendation: (_) {},
              onFeedback: (_, _) {},
              onDislikeFeedback: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('没用'));
    await tester.pump();
    expect(find.byType(InlineDislikeFeedback), findsOneWidget);
    await tester.tap(find.byTooltip('没用'));
    await tester.pump();
    expect(find.byType(InlineDislikeFeedback), findsNothing);
  });

  testWidgets('注入 onReportRecommendation 后长按回调', (tester) async {
    Recommendation? reported;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          favoriteRepositoryProvider.overrideWithValue(_FakeFavoriteRepo()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageBubble(
              message: _msg(
                role: ChatRole.assistant,
                content: '相近导师如下',
                status: ChatMessageStatus.done,
                related: const [_rec],
              ),
              onTapRecommendation: (_) {},
              onReportRecommendation: (r, _, _) => reported = r,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(SwipeRecommendationCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('推荐不准'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(reported?.professorId, _rec.professorId);
  });
}
