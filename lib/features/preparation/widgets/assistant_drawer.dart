import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/assistant_turn.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/feedback.dart';
import '../../../domain/entities/plan_change_card.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../feedback/widgets/feedback_entry_button.dart';
import '../providers/preparation_assistant_controller.dart';
import '../providers/preparation_providers.dart';
import '../../chat/widgets/chat_message_bubble.dart';
import '../widgets/assistant_turn_message_mapper.dart';
import '../widgets/plan_change_card_view.dart';

/// 备赛日历 AI 助手抽屉（spec §3.4 / P4a.5 + P4b.2）：会话状态全部从
/// [preparationAssistantControllerProvider] 读取，本 widget 仅持有输入框与
/// 滚动控制器。发送/接受/拒绝/清理均委托给 controller；渲染历史轮次
/// （经 [AssistantTurnMessageMapper] + [ChatMessageBubble]）与改动卡
/// （横滑 [PlanChangeCardView]）。Header 提供「清理上下文」入口。
class PreparationAssistantDrawer extends ConsumerStatefulWidget {
  const PreparationAssistantDrawer({
    super.key,
    required this.planId,
    required this.plan,
  });

  final String planId;
  final PreparationPlan plan;

  @override
  ConsumerState<PreparationAssistantDrawer> createState() =>
      _PreparationAssistantDrawerState();
}

class _PreparationAssistantDrawerState
    extends ConsumerState<PreparationAssistantDrawer> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text;
    _input.clear();
    await ref
        .read(preparationAssistantControllerProvider(widget.planId).notifier)
        .send(text);
    _scrollToBottom();
  }

  bool get _canSubmit => _input.text.trim().isNotEmpty && !_sending;

  bool get _sending =>
      ref.read(preparationAssistantControllerProvider(widget.planId)).sending;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      preparationAssistantControllerProvider(widget.planId),
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _Header(
              title:
                  state.currentPlan?.competition.name ??
                  widget.plan.competition.name,
              sending: state.sending,
              onClear: () => _confirmClear(context),
            ),
            Expanded(child: _buildConversation(state)),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildConversation(PreparationAssistantControllerState state) {
    final messages = <Widget>[];
    for (final turn in state.turns) {
      final pair = AssistantTurnMessageMapper.toMessages(turn, widget.planId);
      messages.add(
        Padding(
          key: ValueKey('${turn.id}_user'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ChatMessageBubble(
            message: pair[0],
            onTapRecommendation: (_) {},
          ),
        ),
      );
      messages.add(
        Padding(
          key: ValueKey('${turn.id}_assistant'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ChatMessageBubble(
            message: pair[1],
            error:
                turn.error &&
                    state.turns.isNotEmpty &&
                    turn.id == state.turns.last.id
                ? state.lastError
                : null,
            onTapRecommendation: (_) {},
          ),
        ),
      );
      if (!turn.error && turn.changeSet != null) {
        final cards = turn.changeSet!.cards;
        final statuses = state.cardStatuses[turn.id] ?? const {};
        if (_allCardsRejected(cards, statuses)) {
          messages.add(
            _RejectedChangeSetHint(
              key: ValueKey('${turn.id}_all_rejected_hint'),
            ),
          );
        }
        messages.add(
          _ChangeCardRow(
            key: ValueKey('${turn.id}_cards'),
            turn: turn,
            cards: cards,
            statuses: statuses,
            applying: state.applying,
            errors: state.cardErrors,
            onAccept: (card) => ref
                .read(
                  preparationAssistantControllerProvider(
                    widget.planId,
                  ).notifier,
                )
                .acceptCard(turn, card),
            onDecline: (card) => ref
                .read(
                  preparationAssistantControllerProvider(
                    widget.planId,
                  ).notifier,
                )
                .declineCard(turn, card),
          ),
        );
      }
    }
    if (state.pendingUserMessage != null) {
      messages.add(
        Padding(
          key: ValueKey('${widget.planId}_pending_user'),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ChatMessageBubble(
            message: ChatMessage(
              id: '${widget.planId}_pending_user',
              role: ChatRole.user,
              content: state.pendingUserMessage!,
              createdAt: DateTime.now(),
              relatedRecommendations: const [],
              status: ChatMessageStatus.done,
            ),
            onTapRecommendation: (_) {},
          ),
        ),
      );
    }
    if (state.sending) {
      messages.add(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (messages.isEmpty) {
      messages.add(_buildEmptyHint());
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: messages,
    );
  }

  bool _allCardsRejected(
    List<PlanChangeCard> cards,
    Map<String, ChangeCardStatus> statuses,
  ) {
    return cards.isNotEmpty &&
        cards.every(
          (card) =>
              (statuses[card.id] ?? card.status) == ChangeCardStatus.rejected,
        );
  }

  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      child: Column(
        children: [
          Icon(Icons.auto_awesome, size: 36, color: AppColors.indigo),
          const SizedBox(height: 12),
          Text(
            '告诉助手你想怎么调整计划',
            style: TextStyle(color: AppColors.inkSoft, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              enabled: !_sending,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: '输入你的调整需求…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: _canSubmit
                ? AppColors.indigo
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _canSubmit ? _send : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.arrow_upward,
                  color: _canSubmit ? Colors.white : AppColors.inkSoft,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    if (_sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清理上下文'),
        content: const Text('清理上下文会清空本计划的助手对话历史，但不删除计划本身。确认清理？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(preparationAssistantControllerProvider(widget.planId).notifier)
        .clearContext();
  }
}

class _RejectedChangeSetHint extends StatelessWidget {
  const _RejectedChangeSetHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '本轮没有可直接应用的调整，建议重新生成或换个更具体的需求。',
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.sending,
    required this.onClear,
  });

  final String title;
  final bool sending;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 20, color: AppColors.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '竞航小助手',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  title,
                  style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清理上下文',
            onPressed: sending ? null : onClear,
          ),
          FeedbackEntryButton(
            type: FeedbackType.bug,
            route: '/preparation-plans',
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _ChangeCardRow extends StatelessWidget {
  const _ChangeCardRow({
    super.key,
    required this.turn,
    required this.cards,
    required this.statuses,
    required this.applying,
    required this.errors,
    required this.onAccept,
    required this.onDecline,
  });

  final AssistantTurn turn;
  final List<PlanChangeCard> cards;
  final Map<String, ChangeCardStatus> statuses;
  final Set<String> applying;
  final Map<String, String> errors;
  final ValueChanged<PlanChangeCard> onAccept;
  final ValueChanged<PlanChangeCard> onDecline;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final card = cards[i];
          return PlanChangeCardView(
            key: ValueKey('${turn.id}_${card.id}'),
            card: card,
            status: statuses[card.id] ?? card.status,
            errorMessage: errors[card.id],
            applying: applying.contains(card.id),
            onAccept: () => onAccept(card),
            onDecline: () => onDecline(card),
          );
        },
      ),
    );
  }
}
