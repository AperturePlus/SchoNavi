import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'package:flutter/services.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/platform/system_share_platform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/recommendation.dart';
import '../../../shared/widgets/thinking_indicator.dart';
import '../../../shared/widgets/error_details_sheet.dart';
import '../../../shared/utils/share_text_builder.dart';
import 'inline_dislike_feedback.dart';
import 'recommendation_carousel.dart';
import 'recommendation_feedback_sheet.dart';

/// 单条对话气泡：用户右侧纯文本；助手左侧 Markdown；助手可嵌入横向滑动推荐卡片。
class ChatMessageBubble extends ConsumerWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onTapRecommendation,
    this.onOpenHomepage,
    this.onReportRecommendation,
    this.onRetryRecommendation,
    this.onRegenerate,
    this.onFeedback,
    this.onDislikeFeedback,
    this.onRerouteHome,
    this.feedbackSessionId,
    this.feedbackUserPrompt,
    this.error,
  });

  final ChatMessage message;
  final void Function(String professorId) onTapRecommendation;
  final void Function(Recommendation recommendation)? onOpenHomepage;
  final void Function(
    Recommendation recommendation,
    String reason,
    String? note,
  )?
  onReportRecommendation;
  final void Function(String messageId)? onRetryRecommendation;
  final void Function(String messageId)? onRegenerate;
  final void Function(String messageId, ChatMessageFeedback feedback)?
  onFeedback;
  final void Function(String messageId, String content)? onDislikeFeedback;
  final VoidCallback? onRerouteHome;
  final String? feedbackSessionId;
  final String? feedbackUserPrompt;
  final AppException? error;

  /// AI 回复正文统一行高（spec §4.6 可测试常量），上机后微调。
  ///
  /// gpt_markdown 的叶子 TextSpan 用 `config.style ?? const TextStyle()`，
  /// 不会从外层 [DefaultTextStyle] 继承 height，所以必须显式把 style 传给
  /// [GptMarkdown]，否则这里设多少都被 `const TextStyle()` 覆盖成默认行距。
  static const double assistantLineHeight = 1.6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThinking =
        message.status == ChatMessageStatus.sending ||
        (message.status == ChatMessageStatus.streaming &&
            message.content.isEmpty);
    if (isThinking) {
      return const ThinkingIndicator();
    }

    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == ChatRole.user;
    final isError =
        message.status == ChatMessageStatus.error ||
        message.status == ChatMessageStatus.interrupted;
    final isRecommendationError =
        isError && message.kind == ChatMessageKind.recommendation;
    final isStreaming = message.status == ChatMessageStatus.streaming;
    final canShare =
        ref.read(systemSharePlatformProvider).isSupported &&
        message.role == ChatRole.assistant &&
        message.status == ChatMessageStatus.done &&
        message.kind != ChatMessageKind.forkReroute &&
        message.content.trim().isNotEmpty;

    final assistantStyle = DefaultTextStyle.of(
      context,
    ).style.copyWith(height: ChatMessageBubble.assistantLineHeight);

    final Widget body;
    if (isError && !isRecommendationError) {
      body = _AssistantErrorView(
        message: message,
        error: error,
        onRetry: onRegenerate == null ? null : () => onRegenerate!(message.id),
      );
    } else if (isUser) {
      body = Text(message.content);
    } else {
      body = DefaultTextStyle(
        style: assistantStyle,
        child: GptMarkdown(message.content, style: assistantStyle),
      );
    }
    final Widget content = (isStreaming && !isError)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              body,
              const SizedBox(height: 6),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 6),
                  Text('生成中…', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          )
        : body;
    // 仅用户消息保留可选中区域（错误态由 _AssistantErrorView 自管）。
    final Widget selectableContent = isUser
        ? content
        : (isError ? content : SelectionArea(child: content));

    final double maxWidth = math.min(
      360.0,
      MediaQuery.sizeOf(context).width * 0.78,
    );

    final Widget messageBody = isUser
        ? Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(maxWidth: maxWidth),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: selectableContent,
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: selectableContent,
          );

    return Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        messageBody,
        if (message.relatedRecommendations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RecommendationCarousel(
              key: ValueKey('recommendations-${message.id}'),
              recommendations: message.relatedRecommendations,
              onTap: onTapRecommendation,
              onOpenHomepage: onOpenHomepage,
              onReportRecommendation: onReportRecommendation == null
                  ? null
                  : (r) async {
                      final res = await showRecommendationFeedbackSheet(
                        context: context,
                        professorName: r.name,
                      );
                      if (res == null) return;
                      onReportRecommendation!(r, res.$1, res.$2);
                    },
            ),
          ),
        if (message.kind == ChatMessageKind.recommendation &&
            message.status == ChatMessageStatus.error &&
            onRetryRecommendation != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2, bottom: 6),
            child: FilledButton.icon(
              onPressed: () => onRetryRecommendation!(message.id),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试推荐'),
            ),
          ),
        if (_showActions || canShare)
          _MessageActions(
            message: message,
            onShare: canShare ? () => _shareMessage(context, ref) : null,
            onRegenerate: onRegenerate,
            onFeedback: onFeedback,
            onDislikeFeedback: onDislikeFeedback,
            onRetryRecommendation: onRetryRecommendation,
            feedbackSessionId: feedbackSessionId,
            feedbackUserPrompt: feedbackUserPrompt,
          ),
        if (message.kind == ChatMessageKind.forkReroute &&
            message.status == ChatMessageStatus.done &&
            onRerouteHome != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('继续问这位'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onRerouteHome,
                    child: const Text('回首页重挑 ›'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool get _showActions =>
      message.role == ChatRole.assistant &&
      message.kind != ChatMessageKind.forkReroute &&
      message.status == ChatMessageStatus.done &&
      (onRegenerate != null ||
          onFeedback != null ||
          onRetryRecommendation != null ||
          onDislikeFeedback != null);

  Future<void> _shareMessage(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(systemSharePlatformProvider)
        .shareText(ShareTextBuilder.assistantReply(message.content));
    if (!context.mounted) return;
    switch (result) {
      case SystemShareResult.launched:
        return;
      case SystemShareResult.unavailable:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前设备未找到可用的分享应用')),
        );
      case SystemShareResult.failed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('打开系统分享失败，请稍后重试')));
    }
  }
}

class _MessageActions extends StatefulWidget {
  const _MessageActions({
    required this.message,
    this.onShare,
    this.onRegenerate,
    this.onFeedback,
    this.onDislikeFeedback,
    this.onRetryRecommendation,
    this.feedbackSessionId,
    this.feedbackUserPrompt,
  });

  final ChatMessage message;
  final Future<void> Function()? onShare;
  final void Function(String messageId)? onRegenerate;
  final void Function(String messageId, ChatMessageFeedback feedback)?
  onFeedback;
  final void Function(String messageId, String content)? onDislikeFeedback;
  final void Function(String messageId)? onRetryRecommendation;
  final String? feedbackSessionId;
  final String? feedbackUserPrompt;

  @override
  State<_MessageActions> createState() => _MessageActionsState();
}

class _MessageActionsState extends State<_MessageActions> {
  bool _dislikeExpanded = false;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final inactiveColor = AppColors.inkSoft;
    final activeColor = AppColors.indigo;
    final m = widget.message;
    final isRecommendation = m.kind == ChatMessageKind.recommendation;

    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                tooltip: '复制',
                icon: Icons.copy_outlined,
                onPressed: () async {
                  try {
                    await Clipboard.setData(ClipboardData(text: m.content));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制')));
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('复制失败')));
                    }
                  }
                },
              ),
              if (widget.onShare != null)
                _ActionButton(
                  tooltip: '分享',
                  icon: Icons.share_outlined,
                  loading: _sharing,
                  onPressed: _sharing ? null : _share,
                ),
              if (isRecommendation && widget.onRetryRecommendation != null)
                _ActionButton(
                  tooltip: '重新生成推荐',
                  icon: Icons.refresh,
                  onPressed: () => widget.onRetryRecommendation!(m.id),
                )
              else if (!isRecommendation && widget.onRegenerate != null)
                _ActionButton(
                  tooltip: '重新生成',
                  icon: Icons.refresh,
                  onPressed: () => widget.onRegenerate!(m.id),
                ),
              _ActionButton(
                tooltip: '有用',
                icon: m.feedback == ChatMessageFeedback.like
                    ? Icons.thumb_up
                    : Icons.thumb_up_outlined,
                color: m.feedback == ChatMessageFeedback.like
                    ? activeColor
                    : inactiveColor,
                onPressed: widget.onFeedback == null
                    ? null
                    : () => widget.onFeedback!(
                        m.id,
                        m.feedback == ChatMessageFeedback.like
                            ? ChatMessageFeedback.none
                            : ChatMessageFeedback.like,
                      ),
              ),
              _ActionButton(
                tooltip: '没用',
                icon: m.feedback == ChatMessageFeedback.dislike
                    ? Icons.thumb_down
                    : Icons.thumb_down_outlined,
                color: m.feedback == ChatMessageFeedback.dislike
                    ? activeColor
                    : inactiveColor,
                onPressed: widget.onFeedback == null
                    ? null
                    : () {
                        final willDislike = !_dislikeExpanded;
                        widget.onFeedback!(
                          m.id,
                          willDislike
                              ? ChatMessageFeedback.dislike
                              : ChatMessageFeedback.none,
                        );
                        setState(() => _dislikeExpanded = willDislike);
                      },
              ),
            ],
          ),
          if (_dislikeExpanded && widget.onDislikeFeedback != null)
            InlineDislikeFeedback(
              onSubmit: (content) => widget.onDislikeFeedback!(m.id, content),
              onCollapse: () => setState(() => _dislikeExpanded = false),
            ),
        ],
      ),
    );
  }

  Future<void> _share() async {
    final callback = widget.onShare;
    if (callback == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await callback();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.icon,
    this.color,
    this.loading = false,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color? color;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      color: color,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _AssistantErrorView extends StatefulWidget {
  const _AssistantErrorView({required this.message, this.error, this.onRetry});

  final ChatMessage message;
  final AppException? error;
  final VoidCallback? onRetry;

  @override
  State<_AssistantErrorView> createState() => _AssistantErrorViewState();
}

class _AssistantErrorViewState extends State<_AssistantErrorView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showDetails = apiErrorDetailsEnabled(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: cs.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '生成失败，可查看详情或重试',
                  style: TextStyle(color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '查看详情'),
              ),
              if (widget.onRetry != null)
                FilledButton.tonal(
                  onPressed: widget.onRetry,
                  child: const Text('重试'),
                ),
              if (showDetails && widget.error?.diagnostics?.isEmpty == false)
                TextButton.icon(
                  onPressed: () =>
                      showErrorDetailsSheet(context, widget.error!),
                  icon: const Icon(Icons.bug_report_outlined, size: 18),
                  label: const Text('联调详情'),
                ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 28),
              child: Text(
                widget.message.content,
                style: TextStyle(color: cs.error, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
