import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/launcher/link_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/recommendation.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/conversation_session.dart';
import '../../../domain/entities/feedback.dart';
import '../../../domain/entities/fork_ref.dart';
import '../../../shared/widgets/animated_entrance.dart';
import '../../../shared/widgets/api_error_notice.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../../../shared/widgets/cool_scaffold_background.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/floating_top_button.dart';
import '../../../shared/widgets/thinking_indicator.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_quick_actions.dart';
import '../widgets/professor_anchor_bar.dart';
import '../../feedback/providers/feedback_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    this.sessionId,
    this.professorId,
    this.initialPrompt,
    this.forkMode = false,
    this.mainSessionId,
    this.forkId,
    this.sourceTurnId,
  });

  /// 旧入口（从推荐页 FAB / 详情页「继续追问」）：携带已有会话 id 进纯追问。
  final String? sessionId;
  final String? professorId;

  /// 新入口（首页提交）：把提问作为首条用户消息，触发首轮推荐产卡。
  /// 非空时走对话式推荐首轮，隐藏欢迎卡。
  final String? initialPrompt;

  /// fork 追问入口：从教授详情/历史 fork 列表进来。
  final bool forkMode;
  final String? mainSessionId;
  final String? forkId;
  final String? sourceTurnId;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final _provider = chatProvider(Object());
  int _messageCount = 0;

  bool get _configurationBlocked {
    final config = ref.read(appConfigProvider);
    return config.dataSource == DataSource.llm && !config.llm.isConfigured;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_configurationBlocked) return;
      final notifier = ref.read(_provider.notifier);
      if (widget.sessionId != null && widget.sessionId!.trim().isNotEmpty) {
        await notifier.resume(sessionId: widget.sessionId!.trim());
        return;
      }
      if (widget.forkMode && widget.forkId != null) {
        await notifier.resume(
          sessionId: widget.forkId!,
          isFork: true,
          mainSessionId: widget.mainSessionId,
        );
        return;
      }
      if (widget.forkMode) {
        await notifier.startFork(
          sourceSessionId: widget.mainSessionId ?? '',
          professorId: widget.professorId ?? '',
          sourceTurnId: widget.sourceTurnId,
        );
        return;
      }
      await notifier.create(professorId: widget.professorId);
      if (widget.initialPrompt != null &&
          widget.initialPrompt!.trim().isNotEmpty) {
        await notifier.bootstrapRecommendations(widget.initialPrompt!);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    _controller.clear();
    ref.read(_provider.notifier).send(value);
  }

  Future<void> _openHomepage(Recommendation recommendation) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(linkLauncherProvider)
        .open(recommendation.homepageUrl);
    switch (result) {
      case LaunchResult.success:
        return;
      case LaunchResult.noUrl:
        messenger.showSnackBar(const SnackBar(content: Text('暂无主页信息')));
      case LaunchResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('主页可能已失效，可通过学校官网确认')),
        );
    }
  }

  bool _isStreaming(ChatState state) =>
      state.activity == ChatActivity.streaming;

  bool _showPendingThinking(ChatState state) {
    final waitingForFirstAssistant = switch (state.activity) {
      ChatActivity.classifying ||
      ChatActivity.connecting ||
      ChatActivity.recommending ||
      ChatActivity.committing => true,
      _ => false,
    };
    if (!waitingForFirstAssistant ||
        state.messages.isEmpty ||
        state.messages.last.role != ChatRole.user) {
      return false;
    }
    return !state.messages.any(
      (message) =>
          message.role == ChatRole.assistant &&
          message.id.startsWith('pending-'),
    );
  }

  Future<bool> _confirmExit(BuildContext context) async {
    if (!_isStreaming(ref.read(_provider))) return true;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('正在生成中'),
        content: const Text('当前对话正在生成，离开会中断本轮。要离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续生成'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('离开'),
          ),
        ],
      ),
    );
    if (shouldLeave == true) {
      await ref.read(_provider.notifier).stop();
    }
    return shouldLeave ?? false;
  }

  Future<void> _handleBack(BuildContext context) async {
    final shouldLeave = await _confirmExit(context);
    if (shouldLeave && context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final blocked =
        config.dataSource == DataSource.llm && !config.llm.isConfigured;
    final state = ref.watch(_provider);
    // 首页带 initialPrompt 进来是新会话（对话式推荐首轮），不应显示「继续追问」
    // 这种「延续旧会话」的语义——对齐 ChatGPT App：新对话就是新对话页。
    final isNewSession = widget.initialPrompt != null;
    final isLoadingSession =
        state.activity == ChatActivity.unloaded ||
        state.activity == ChatActivity.creating ||
        state.activity == ChatActivity.hydrating ||
        state.activity == ChatActivity.deleting;
    final showWelcome = widget.initialPrompt == null && !isLoadingSession;
    final showPendingThinking = _showPendingThinking(state);
    final itemCount =
        state.messages.length +
        (showWelcome ? 1 : 0) +
        (showPendingThinking ? 1 : 0);
    if (itemCount != _messageCount) {
      _messageCount = itemCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
    return PopScope(
      canPop: !_isStreaming(state),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit(context);
        if (shouldLeave && context.mounted) context.pop();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: CoolScaffoldBackground()),
            blocked
                ? ErrorView(error: const MissingLlmConfigurationException())
                : state.activity == ChatActivity.loadFailed
                ? ErrorView(
                    error:
                        state.error ??
                        const UnknownException(message: '会话加载失败'),
                    onRetry: () {
                      final sid = widget.sessionId ?? widget.forkId;
                      if (sid != null && sid.isNotEmpty) {
                        ref.read(_provider.notifier).resume(sessionId: sid);
                      } else {
                        ref
                            .read(_provider.notifier)
                            .create(professorId: widget.professorId);
                      }
                    },
                  )
                : SafeArea(
                    child: Column(
                      children: [
                        if (state.activity == ChatActivity.creating ||
                            state.activity == ChatActivity.hydrating ||
                            state.activity == ChatActivity.deleting)
                          _ChatStateNotice(
                            message: switch (state.activity) {
                              ChatActivity.creating => '正在创建会话…',
                              ChatActivity.hydrating => '正在恢复会话与上下文…',
                              ChatActivity.deleting => '正在删除会话…',
                              _ => '',
                            },
                            showProgress: true,
                          ),
                        if (state.activity == ChatActivity.interrupted ||
                            state.activity == ChatActivity.turnFailed)
                          _ChatStateNotice(
                            message:
                                state.errorMessage ??
                                (state.activity == ChatActivity.interrupted
                                    ? '上次生成已中断，部分内容已保存。'
                                    : '本轮处理失败，可以重试同一轮。'),
                            error: state.error,
                            primaryLabel: state.canRegenerate ? '重试本轮' : null,
                            onPrimary: state.canRegenerate
                                ? () =>
                                      ref.read(_provider.notifier).regenerate()
                                : null,
                            secondaryLabel: '放弃本轮',
                            onSecondary: () => ref
                                .read(_provider.notifier)
                                .abandonInterruptedTurn(),
                          ),
                        if (state.legacyContextIncomplete)
                          _ChatStateNotice(
                            message: '旧分支的来源推荐轮次无法准确恢复，当前仅供只读查看。',
                            primaryLabel: '新建会话',
                            onPrimary: () => ref
                                .read(_provider.notifier)
                                .create(professorId: state.professorId),
                          ),
                        Expanded(
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.fromLTRB(
                              20,
                              state.forkAnchor != null ? 108.0 : 56.0,
                              20,
                              12,
                            ),
                            itemCount: itemCount,
                            itemBuilder: (context, index) {
                              if (showWelcome && index == 0) {
                                return AnimatedEntrance(
                                  index: 0,
                                  slideOffset: const Offset(0, 12),
                                  duration: const Duration(milliseconds: 300),
                                  child: _WelcomeCard(
                                    professorName:
                                        state.forkAnchor?.professorName,
                                  ),
                                );
                              }
                              final messageIndex = showWelcome
                                  ? index - 1
                                  : index;
                              if (showPendingThinking &&
                                  messageIndex == state.messages.length) {
                                return const AnimatedEntrance(
                                  index: 0,
                                  slideOffset: Offset(0, 12),
                                  duration: Duration(milliseconds: 300),
                                  child: ThinkingIndicator(),
                                );
                              }
                              return AnimatedEntrance(
                                index: index,
                                slideOffset: const Offset(0, 12),
                                duration: const Duration(milliseconds: 300),
                                child: ChatMessageBubble(
                                  key: ValueKey(
                                    state.messages[messageIndex].id,
                                  ),
                                  message: state.messages[messageIndex],
                                  error:
                                      state.messages[messageIndex].status ==
                                          ChatMessageStatus.error
                                      ? state.error
                                      : null,
                                  onTapRecommendation: (id) {
                                    final sid =
                                        state.kind ==
                                            ConversationSessionKind.fork
                                        ? state.sourceSessionId
                                        : state.sessionId;
                                    final turnId = _turnIdForMessageIndex(
                                      state,
                                      messageIndex,
                                    );
                                    final query = <String, String>{
                                      'msid': ?sid,
                                      'stid': ?turnId,
                                    };
                                    context.push(
                                      Uri(
                                        path: '/professor/$id',
                                        queryParameters: query.isEmpty
                                            ? null
                                            : query,
                                      ).toString(),
                                    );
                                  },
                                  onOpenHomepage: _openHomepage,
                                  onRerouteHome: () => context.go('/home'),
                                  onRetryRecommendation: (id) => ref
                                      .read(_provider.notifier)
                                      .retryRecommendation(id),
                                  onRegenerate: (id) => ref
                                      .read(_provider.notifier)
                                      .regenerateMessage(id),
                                  onFeedback: (id, feedback) => ref
                                      .read(_provider.notifier)
                                      .setFeedback(id, feedback),
                                  onDislikeFeedback: (id, content) =>
                                      _submitMessageFeedback(
                                        id,
                                        content,
                                        messageIndex,
                                      ),
                                  onReportRecommendation: (r, reason, note) =>
                                      _submitRecommendationFeedback(
                                        r,
                                        reason,
                                        note,
                                        messageIndex,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                        ChatQuickActions(
                          actions: state.followUpQuestions,
                          enabled: state.canSend,
                          onTap: _send,
                        ),
                        ChatInputBar(
                          controller: _controller,
                          isBusy: !state.canSend,
                          canStop: state.activity == ChatActivity.streaming,
                          isNewSession: isNewSession,
                          onSubmit: _send,
                          onStop: () => ref.read(_provider.notifier).stop(),
                        ),
                      ],
                    ),
                  ),
            if (state.forkAnchor != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: ProfessorAnchorBar(
                    anchor: state.forkAnchor!,
                    onTap: () => context.push(
                      '/professor/${state.forkAnchor!.professorId}'
                      '?msid=${Uri.encodeComponent(state.sourceSessionId ?? state.forkAnchor!.mainSessionId)}'
                      '${state.sourceTurnId == null ? '' : '&stid=${Uri.encodeComponent(state.sourceTurnId!)}'}',
                    ),
                    // fork 追问页：把「返回」「重新生成」收进锚点条同一行，
                    // 避免它们作为独立 Positioned 与锚点条在顶部重叠。
                    leading: FloatingTopButton(
                      icon: Icons.arrow_back,
                      tooltip: '返回',
                      onPressed: () => _handleBack(context),
                    ),
                    trailing: FloatingTopButton(
                      icon: Icons.refresh,
                      tooltip: '重新生成',
                      onPressed: state.canRegenerate
                          ? () => ref.read(_provider.notifier).regenerate()
                          : null,
                    ),
                  ),
                ),
              )
            else ...[
              // 左上悬浮：新会话页（initialPrompt 首页提交入口）显示「新对话」
              // 回首页；旧会话追问页（推荐页/详情页「继续追问」push 进来）显示
              // 「返回」，pop 回上一页而非丢弃会话跳首页。
              Positioned(
                top: 8,
                left: 12,
                child: isNewSession
                    ? FloatingTopButton(
                        icon: Icons.edit_square,
                        tooltip: '新对话',
                        onPressed: () => context.go('/home'),
                      )
                    : FloatingTopButton(
                        icon: Icons.arrow_back,
                        tooltip: '返回',
                        onPressed: () => _handleBack(context),
                      ),
              ),
              // 右上悬浮：「重新生成」；canRegenerate=false 时 disabled。
              Positioned(
                top: 8,
                right: 12,
                child: FloatingTopButton(
                  icon: Icons.refresh,
                  tooltip: '重新生成',
                  onPressed: state.canRegenerate
                      ? () => ref.read(_provider.notifier).regenerate()
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _turnIdForMessageIndex(ChatState state, int messageIndex) {
    if (messageIndex < 0 || state.turns.isEmpty) return null;
    var assistantOrdinal = -1;
    for (var i = 0; i <= messageIndex && i < state.messages.length; i++) {
      if (state.messages[i].role == ChatRole.user) assistantOrdinal++;
    }
    if (assistantOrdinal < 0 || assistantOrdinal >= state.turns.length) {
      return null;
    }
    return state.turns[assistantOrdinal].id;
  }

  String? _userPromptForMessageIndex(ChatState state, int messageIndex) {
    for (var i = messageIndex; i >= 0; i--) {
      if (state.messages[i].role == ChatRole.user) {
        return state.messages[i].content;
      }
    }
    return null;
  }

  Future<void> _submitMessageFeedback(
    String messageId,
    String content,
    int messageIndex,
  ) async {
    final state = ref.read(_provider);
    final messages = state.messages;
    final i = messages.indexWhere((m) => m.id == messageId);
    final type = (i >= 0 && messages[i].kind == ChatMessageKind.recommendation)
        ? FeedbackType.recommendation
        : FeedbackType.other;
    final ctx =
        FeedbackContext(
          messageId: messageId,
          sessionId: state.sessionId,
          prompt: _userPromptForMessageIndex(state, messageIndex),
        ).copyWith(
          appVersion: ref.read(appConfigProvider).appVersion,
          dataSourceMode: ref.read(appConfigProvider).dataSource.name,
        );
    final ok = await ref
        .read(feedbackSubmitProvider.notifier)
        .submit(
          type: type,
          content: content.isEmpty ? '点踩反馈（无文字）' : content,
          context: ctx,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '感谢反馈' : '反馈提交失败,请稍后重试')));
  }

  Future<void> _submitRecommendationFeedback(
    Recommendation r,
    String reason,
    String? note,
    int messageIndex,
  ) async {
    final state = ref.read(_provider);
    final ctx =
        FeedbackContext(
          professorId: r.professorId,
          sessionId: state.sessionId,
          prompt: _userPromptForMessageIndex(state, messageIndex),
        ).copyWith(
          appVersion: ref.read(appConfigProvider).appVersion,
          dataSourceMode: ref.read(appConfigProvider).dataSource.name,
        );
    final content = note == null || note.isEmpty ? reason : '$reason：$note';
    final ok = await ref
        .read(feedbackSubmitProvider.notifier)
        .submit(
          type: FeedbackType.recommendation,
          content: content,
          context: ctx,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ok ? '感谢反馈' : '反馈提交失败,请稍后重试')));
  }
}

class _ChatStateNotice extends StatelessWidget {
  const _ChatStateNotice({
    required this.message,
    this.error,
    this.showProgress = false,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final AppException? error;
  final bool showProgress;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ApiErrorNotice(
      message: message,
      error: error,
      showProgress: showProgress,
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({this.professorName});

  final String? professorName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final resolvedProfessorName = professorName == forkProfessorUnavailableLabel
        ? null
        : professorName;
    return BentoTile(
      frosted: true,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(
                Icons.chat_bubble_outline,
                color: AppColors.indigo,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resolvedProfessorName == null
                      ? '有什么想追问的？'
                      : '关于$resolvedProfessorName教授，想继续问什么？',
                  style: textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            resolvedProfessorName == null
                ? '我可以基于上一步的推荐继续解答。试试问我：为什么推荐、相似导师、只看某地、是否适合硕士 / 博士。'
                : '我会参考上一轮的需求与推荐依据，但这里仅显示围绕该教授的新对话。'
                      '可以问：为什么适合我、研究方向、硕博匹配、联系前准备。',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
