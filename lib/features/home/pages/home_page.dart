import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/inline_tag_input.dart';

import '../../../core/di/providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/launcher/link_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/home_config.dart';
import '../../../domain/entities/home_prompt.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/feedback.dart';
import '../../../domain/entities/recommendation.dart';
import '../../../domain/entities/search_history_item.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/widgets/chat_message_bubble.dart';
import '../../chat/widgets/chat_quick_actions.dart';
import '../../feedback/providers/feedback_provider.dart';
import '../../competition_recommendation/providers/competition_home_notifier.dart';
import '../../competition_recommendation/widgets/competition_home_result_view.dart';
import '../../../shared/widgets/animated_entrance.dart';
import '../../../shared/widgets/app_menu_drawer.dart';
import '../../../shared/widgets/api_error_notice.dart';
import '../../../shared/widgets/bento_grid.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../../../shared/widgets/cool_scaffold_background.dart';
import '../../../shared/widgets/floating_top_button.dart';
import '../../../shared/widgets/glass_surface.dart';
import '../../../shared/widgets/right_edge_open_drawer.dart';
import '../../../shared/widgets/rotating_subtitle.dart';
import '../../../shared/widgets/scho_navi_logo.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/widgets/sliding_pill_switch.dart';
import '../../../shared/widgets/thinking_indicator.dart';
import '../../../shared/widgets/error_view.dart';

/// 首页双 tab：导师推荐 / 竞赛推荐。公开以供路由层按 `?tab=` 预选。
enum HomeTab { mentor, competition }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({
    super.key,
    this.initialTab = HomeTab.mentor,
    this.historySessionId,
  });

  final HomeTab initialTab;
  final String? historySessionId;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

/// 首页副标题动效。后期可替换为 FadeSlideStrategy() / CrossfadeStrategy()。
const SubtitleAnimationStrategy _kSubtitleStrategy = TypewriterStrategy();

class _TabConfig {
  const _TabConfig({required this.taglines});

  final List<String> taglines;
}

class _HomePageState extends ConsumerState<HomePage> {
  static const int _maxLen = 1000;
  final InlineTagController _controller = InlineTagController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _conversationScrollController = ScrollController();
  late final _chatProvider = chatProvider(Object());
  bool _focused = false;
  bool _submitting = false;
  bool _inConversation = false;
  bool _inConversationStarted = false;
  String? _competitionPrompt;
  String? _handledHistorySessionId;
  int _messageCount = 0;
  late HomeTab _currentTab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(
      () => setState(() => _focused = _focusNode.hasFocus),
    );
    _controller.addListener(() => setState(() {}));
    _scheduleCompetitionHistoryRestore();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _currentTab = widget.initialTab;
    }
    if (oldWidget.historySessionId != widget.historySessionId) {
      _handledHistorySessionId = null;
    }
    _scheduleCompetitionHistoryRestore();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    _conversationScrollController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _controller.plainText.trim().isNotEmpty && !_submitting;

  void _scheduleCompetitionHistoryRestore() {
    final sessionId = widget.historySessionId?.trim();
    if (widget.initialTab != HomeTab.competition ||
        sessionId == null ||
        sessionId.isEmpty ||
        _handledHistorySessionId == sessionId) {
      return;
    }
    _handledHistorySessionId = sessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_restoreCompetitionHistory(sessionId));
    });
  }

  Future<void> _restoreCompetitionHistory(String sessionId) async {
    setState(() {
      _currentTab = HomeTab.competition;
      _inConversation = true;
      _competitionPrompt = null;
    });

    SearchHistoryItem? item = _cachedCompetitionHistory(sessionId);
    if (item?.competitionResult == null) {
      try {
        item = await ref
            .read(historyRepositoryProvider)
            .getBySessionId(sessionId, type: SearchHistoryType.competition);
      } catch (error, stackTrace) {
        if (!mounted) return;
        ref
            .read(apiErrorReporterProvider.notifier)
            .report('竞赛历史恢复失败', error, stackTrace);
        ref
            .read(competitionHomeProvider.notifier)
            .showHistorySummary(
              normalizeAppException(error, stackTrace).message,
            );
        return;
      }
    }
    if (!mounted) return;
    if (item == null) {
      ref
          .read(competitionHomeProvider.notifier)
          .showHistorySummary('历史记录不存在或已被删除');
      return;
    }

    setState(() => _competitionPrompt = item!.prompt);
    final result = item.competitionResult;
    if (result != null) {
      ref.read(competitionHomeProvider.notifier).restoreResult(result);
    } else {
      ref
          .read(competitionHomeProvider.notifier)
          .showHistorySummary(item.summary);
    }
  }

  SearchHistoryItem? _cachedCompetitionHistory(String sessionId) {
    final history = ref.read(searchHistoryProvider).asData?.value;
    if (history == null) return null;
    for (final item in history) {
      if (item.type == SearchHistoryType.competition &&
          item.sessionId == sessionId) {
        return item;
      }
    }
    return null;
  }

  /// 导师 tab / 竞赛 tab 均首页原地响应：发送后不跳路由。
  /// 导师进入对话态，竞赛进入结果态。
  Future<void> _submit() async {
    final prompt = _controller.plainText.trim();
    if (prompt.isEmpty || _submitting) return;
    final config = ref.read(appConfigProvider);
    if (!config.api.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(const MissingApiConfigurationException().message),
        ),
      );
      return;
    }
    final isMentor = _currentTab == HomeTab.mentor;
    if (prompt.length < 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('可补充研究方向或地区，描述更具体会更准哦')));
    }

    if (!isMentor) {
      // 竞赛 tab：首页原地进入结果态，由 CompetitionHomeResultView 渲染推荐卡。
      setState(() {
        _submitting = true;
        _inConversation = true;
        _competitionPrompt = prompt;
      });
      final promptValue = prompt;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await ref.read(competitionHomeProvider.notifier).submit(promptValue);
      });
      _controller.clear();
      setState(() => _submitting = false);
      return;
    }

    // 导师 tab：原地启动对话。已有对话态则走追问 send；否则开局首推产卡。
    // autoDispose provider：落地态无人 watch，必须先 setState 进对话态让
    // _buildConversationContent 订阅，再在下一帧启动 notifier，否则 notifier
    // 会在 read 结束后被自动释放、状态丢失。
    setState(() {
      _submitting = true;
      _inConversation = true;
    });
    final promptValue = prompt;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(_chatProvider.notifier);
      if (!_inConversationStarted) {
        _inConversationStarted = true;
        await notifier.create();
        if (!mounted) return;
        await notifier.bootstrapRecommendations(promptValue);
      } else {
        await notifier.send(promptValue);
      }
    });
    _controller.clear();
    setState(() => _submitting = false);
  }

  void _sendFollowUp(String text) {
    final value = text.trim();
    if (value.isEmpty) return;
    ref.read(_chatProvider.notifier).send(value);
  }

  void _stopGeneration() => ref.read(_chatProvider.notifier).stop();

  void _startNewConversation() {
    if (_currentTab == HomeTab.competition) {
      ref.read(competitionHomeProvider.notifier).reset();
      setState(() {
        _inConversation = false;
        _competitionPrompt = null;
      });
      _controller.clear();
      return;
    }
    setState(() {
      _inConversation = false;
      _inConversationStarted = false;
      _messageCount = 0;
    });
    ref.invalidate(_chatProvider);
    _controller.clear();
  }

  void _scrollConversationToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_conversationScrollController.hasClients) {
        _conversationScrollController.animateTo(
          _conversationScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  Future<void> _openCompetitionUrl(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(linkLauncherProvider).open(url);
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

  void _adjustCompetition() {
    ref.read(competitionHomeProvider.notifier).reset();
    setState(() {
      _inConversation = false;
      _competitionPrompt = null;
    });
  }

  BentoTile _buildPromptTile(HomePrompt prompt) {
    return BentoTile(
      onTap: () {
        Haptics.light();
        _controller.value = TextEditingValue(
          text: prompt.text,
          selection: TextSelection.collapsed(offset: prompt.text.length),
        );
      },
      frosted: true,
      height: 132,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            prompt.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: Icon(
              Icons.lightbulb_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptGridSkeleton() {
    return BentoGrid(
      crossAxisCount: 2,
      spacing: 12,
      runSpacing: 12,
      animateEntrance: false,
      children: List.generate(
        4,
        (_) => BentoTile(
          frosted: true,
          height: 120,
          padding: const EdgeInsets.all(16),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Skeleton(height: 12, width: double.infinity),
              SizedBox(height: 8),
              Skeleton(height: 12, width: 80),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;
    final homeConfigAsync = ref.watch(homeConfigProvider(_currentTab.name));

    return Scaffold(
      resizeToAvoidBottomInset: true,
      endDrawer: const AppMenuDrawer(),
      drawerEdgeDragWidth: 0,
      body: Builder(
        builder: (context) {
          return Stack(
            children: [
              // 冷调渐变底：玻璃面在其上折射出层次。
              const Positioned.fill(child: CoolScaffoldBackground()),
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        Expanded(
                          child: _inConversation
                              ? _buildConversationContent(textTheme, scheme)
                              : _buildLandingContent(
                                  textTheme,
                                  scheme,
                                  homeConfigAsync,
                                ),
                        ),
                        _buildBottomInput(scheme),
                      ],
                    ),
                  ),
                ),
              ),
              // 左上悬浮：仅对话态出现「新对话」；落地态留空。
              // SafeArea 避让系统状态栏，防止按钮贴顶被遮挡。
              if (_inConversation)
                Positioned(
                  top: 0,
                  left: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 0, 0),
                      child: FloatingTopButton(
                        icon: Icons.edit_square,
                        tooltip: '新对话',
                        onPressed: _startNewConversation,
                      ),
                    ),
                  ),
                ),
              // 右上悬浮：「菜单」常驻。
              Positioned(
                top: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 12, 0),
                    child: FloatingTopButton(
                      icon: Icons.menu_outlined,
                      tooltip: '菜单',
                      onPressed: () {
                        Haptics.light();
                        Scaffold.of(context).openEndDrawer();
                      },
                    ),
                  ),
                ),
              ),
              // Right-edge swipe area. It stops 80 logical pixels above the
              // bottom of the screen, clearing the input bar without stealing
              // taps. top:56 避让右上菜单按钮触控区。
              Positioned(
                top: 56,
                right: 0,
                bottom: 80,
                child: RightEdgeOpenDrawer(
                  onSwipe: () {
                    Haptics.light();
                    Scaffold.of(context).openEndDrawer();
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 落地态：品牌字标 + 模式开关 + 动态副标题 + prompt 网格。
  Widget _buildLandingContent(
    TextTheme textTheme,
    ColorScheme scheme,
    AsyncValue<HomeConfig> homeConfigAsync,
  ) {
    final homeConfig = homeConfigAsync.value;
    final tabConfig = _TabConfig(taglines: homeConfig?.taglines ?? const []);
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedEntrance(
            index: 0,
            child: Padding(
              // 顶部留白 28：避开状态栏后给品牌字标足够呼吸，避免落地态局促。
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
              child: Column(
                children: [
                  // 品牌标，居中 Hero：矢量 logo + indigo→cyan 渐变字标。
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SchoNaviLogo(
                      size: 44,
                      withWordmark: true,
                      wordmarkStyle: textTheme.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 模式切换器，居中放大。
                  SizedBox(
                    width: 200,
                    child: SlidingPillSwitch<HomeTab>(
                      values: const [HomeTab.mentor, HomeTab.competition],
                      selected: _currentTab,
                      labels: const ['导师', '竞赛'],
                      onChanged: (value) {
                        setState(() => _currentTab = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 随模式轮播的动态副标题（固定高度防跳动）。
                  SizedBox(
                    height: 44,
                    child: Center(
                      child: RotatingSubtitle(
                        phrases: tabConfig.taglines,
                        strategy: _kSubtitleStrategy,
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          AnimatedEntrance(
            index: 1,
            child: homeConfigAsync.when(
              data: (config) {
                return BentoGrid(
                  crossAxisCount: 2,
                  spacing: 12,
                  runSpacing: 12,
                  animateEntrance: false,
                  children: config.prompts
                      .take(4)
                      .map(_buildPromptTile)
                      .toList(),
                );
              },
              loading: () => _buildPromptGridSkeleton(),
              error: (error, stackTrace) => ErrorView(
                error: normalizeAppException(error, stackTrace),
                onRetry: () =>
                    ref.invalidate(homeConfigProvider(_currentTab.name)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 竞赛 tab 原地结果态：由 [CompetitionHomeResultView] 渲染需求理解与推荐卡。
  Widget _buildCompetitionResultContent() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
            child: CompetitionHomeResultView(
              state: ref.watch(competitionHomeProvider),
              onAdjust: _adjustCompetition,
              onRetry: (prompt) =>
                  ref.read(competitionHomeProvider.notifier).submit(prompt),
              prompt: _competitionPrompt,
              onOpenDetail: (id) => context.push('/competition/$id'),
              onOpenUrl: _openCompetitionUrl,
            ),
          ),
        ),
      ],
    );
  }

  /// 对话态：消息流（复用 ChatMessageBubble）+ 快捷操作横滑条。
  Widget _buildConversationContent(TextTheme textTheme, ColorScheme scheme) {
    if (_currentTab == HomeTab.competition) {
      return _buildCompetitionResultContent();
    }

    final state = ref.watch(_chatProvider);
    final showPendingThinking = _showPendingThinking(state);
    final renderedItemCount =
        state.messages.length + (showPendingThinking ? 1 : 0);
    if (renderedItemCount != _messageCount) {
      _messageCount = renderedItemCount;
      _scrollConversationToBottom();
    }
    return Column(
      children: [
        if (state.activity == ChatActivity.creating ||
            state.activity == ChatActivity.hydrating)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 56, 20, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在创建并恢复会话上下文…'),
              ],
            ),
          ),
        if (state.activity == ChatActivity.loadFailed ||
            state.activity == ChatActivity.turnFailed ||
            state.activity == ChatActivity.interrupted)
          ApiErrorNotice(
            message:
                state.errorMessage ??
                (state.activity == ChatActivity.interrupted
                    ? '上次生成已中断，部分内容已保存。'
                    : '会话处理失败，请重试。'),
            error: state.error,
            primaryLabel: state.canRegenerate
                ? '重试本轮'
                : state.activity == ChatActivity.loadFailed
                ? '新建会话'
                : null,
            onPrimary: state.canRegenerate
                ? () => ref.read(_chatProvider.notifier).regenerate()
                : state.activity == ChatActivity.loadFailed
                ? _startNewConversation
                : null,
            secondaryLabel: state.activity == ChatActivity.loadFailed
                ? null
                : '放弃本轮',
            onSecondary: state.activity == ChatActivity.loadFailed
                ? null
                : () =>
                      ref.read(_chatProvider.notifier).abandonInterruptedTurn(),
          ),
        Expanded(
          child: ListView.builder(
            controller: _conversationScrollController,
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
            itemCount: renderedItemCount,
            itemBuilder: (context, index) {
              if (showPendingThinking && index == state.messages.length) {
                return const AnimatedEntrance(
                  index: 0,
                  slideOffset: Offset(0, 12),
                  duration: Duration(milliseconds: 300),
                  child: ThinkingIndicator(),
                );
              }
              final message = state.messages[index];
              return AnimatedEntrance(
                index: index,
                slideOffset: const Offset(0, 12),
                duration: const Duration(milliseconds: 300),
                child: ChatMessageBubble(
                  key: ValueKey(message.id),
                  message: message,
                  error: message.status == ChatMessageStatus.error
                      ? state.error
                      : null,
                  onTapRecommendation: (id) {
                    final mainSid = ref.read(_chatProvider).sessionId;
                    final turnId = _turnIdForMessageIndex(state, index);
                    final query = <String, String>{
                      if (mainSid != null && mainSid.isNotEmpty)
                        'msid': mainSid,
                      'stid': ?turnId,
                    };
                    context.push(
                      Uri(
                        path: '/professor/$id',
                        queryParameters: query.isEmpty ? null : query,
                      ).toString(),
                    );
                  },
                  onOpenHomepage: _openHomepage,
                  onRetryRecommendation: (id) =>
                      ref.read(_chatProvider.notifier).retryRecommendation(id),
                  onRegenerate: (id) =>
                      ref.read(_chatProvider.notifier).regenerateMessage(id),
                  onFeedback: (id, feedback) => ref
                      .read(_chatProvider.notifier)
                      .setFeedback(id, feedback),
                  onDislikeFeedback: (id, content) =>
                      _submitMessageFeedback(id, content, index),
                  onReportRecommendation: (r, reason, note) =>
                      _submitRecommendationFeedback(r, reason, note, index),
                  feedbackSessionId: ref.read(_chatProvider).sessionId,
                  feedbackUserPrompt: _userPromptForMessageIndex(state, index),
                ),
              );
            },
          ),
        ),
        ChatQuickActions(
          actions: state.followUpQuestions,
          enabled: state.canSend,
          onTap: _sendFollowUp,
        ),
      ],
    );
  }

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

  /// 底部常驻输入区：落地态用 quick tags，对话态用快捷操作；发送键在
  /// 对话态支持 busy→stop 切换。输入框始终用 InlineTagInput（保留标签能力）。
  Widget _buildBottomInput(ColorScheme scheme) {
    final chatState = _inConversation ? ref.watch(_chatProvider) : null;
    final isBusy = chatState?.isBusy ?? false;
    final canStop = chatState?.activity == ChatActivity.streaming;
    final hint = _inConversation ? '继续描述你的需求…' : '给 SchoNavi 发送消息';
    final focusBorder = Border.all(
      color: _focused
          ? AppColors.indigo
          : scheme.outline.withValues(alpha: 0.32),
      width: _focused ? 2 : 1,
    );
    return AnimatedEntrance(
      index: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassSurface(
              frosted: true,
              radius: 24,
              padding: EdgeInsets.zero,
              border: focusBorder,
              shadow: AppColors.shadowElevated,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: InlineTagInput(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      maxLength: _maxLen,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (_canSubmit && !isBusy) _submit();
                      },
                      hintText: hint,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: _buildSendButton(
                      scheme,
                      isBusy: isBusy,
                      canStop: canStop,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 发送/停止按钮：对话态 streaming 时为停止键，busy 时为 loading 指示，
  /// 否则为发送键。落地态恒为发送键。
  Widget _buildSendButton(
    ColorScheme scheme, {
    required bool isBusy,
    required bool canStop,
  }) {
    if (canStop) {
      return Tooltip(
        message: '停止生成',
        child: Material(
          color: AppColors.indigo,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _stopGeneration,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.stop, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }
    if (isBusy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Tooltip(
      message: '发送',
      child: Material(
        color: _canSubmit ? AppColors.indigo : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _canSubmit
              ? () {
                  Haptics.medium();
                  _submit();
                }
              : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.arrow_upward,
              color: _canSubmit ? Colors.white : scheme.onSurfaceVariant,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  String? _turnIdForMessageIndex(ChatState state, int messageIndex) {
    var turnIndex = -1;
    for (var i = 0; i <= messageIndex && i < state.messages.length; i++) {
      if (state.messages[i].role == ChatRole.user) turnIndex++;
    }
    if (turnIndex < 0 || turnIndex >= state.turns.length) return null;
    return state.turns[turnIndex].id;
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
    final state = ref.read(_chatProvider);
    final messages = state.messages;
    final i = messages.indexWhere((m) => m.id == messageId);
    final type = (i >= 0 && messages[i].kind == ChatMessageKind.recommendation)
        ? FeedbackType.recommendation
        : FeedbackType.other;
    final ctx = FeedbackContext(
      messageId: messageId,
      sessionId: state.sessionId,
      prompt: _userPromptForMessageIndex(state, messageIndex),
    ).copyWith(appVersion: ref.read(appConfigProvider).appVersion);
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
    final state = ref.read(_chatProvider);
    final ctx = FeedbackContext(
      professorId: r.professorId,
      sessionId: state.sessionId,
      prompt: _userPromptForMessageIndex(state, messageIndex),
    ).copyWith(appVersion: ref.read(appConfigProvider).appVersion);
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
