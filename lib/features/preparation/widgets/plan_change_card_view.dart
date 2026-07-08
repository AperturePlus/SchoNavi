import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/plan_change_card.dart';
import '../../../shared/widgets/bento_tile.dart';

/// 改动卡视图（spec §2.6 / P4b.2）：展示 [PlanChangeCard.summary] +
/// [PlanChangeCard.rationale] + 状态胶囊；rejected/stale 时附带原因。
///
/// [status] 为调用方（抽屉）持有的实时状态——实体本身不可变，状态在 UI 层
/// 维护。pending 时启用接受/拒绝；applied/declined/stale/rejected 时折叠或
/// 只读。接受中禁用按钮防重。
class PlanChangeCardView extends StatelessWidget {
  const PlanChangeCardView({
    super.key,
    required this.card,
    required this.status,
    this.errorMessage,
    this.onAccept,
    this.onDecline,
    this.applying = false,
  });

  final PlanChangeCard card;
  final ChangeCardStatus status;
  final String? errorMessage;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final bool applying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusStyle = _statusStyle(status, scheme);
    final rejectionReason = _displayRejectionReason();
    final interactive = status == ChangeCardStatus.pending;
    final folded = status == ChangeCardStatus.declined;
    return BentoTile(
      width: 280,
      color: scheme.surface,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(_typeIcon(card.type), size: 18, color: AppColors.indigo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  card.summary,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: folded ? AppColors.inkFaint : null,
                    decoration: folded ? TextDecoration.lineThrough : null,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (!folded) ...[
            const SizedBox(height: 8),
            Text(
              card.rationale,
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusChip(label: statusStyle.label, color: statusStyle.color),
              if (status == ChangeCardStatus.rejected &&
                  rejectionReason != null)
                Text(
                  rejectionReason,
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (status == ChangeCardStatus.stale)
                const Text(
                  '计划已变化，请重新生成建议',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              if (status == ChangeCardStatus.pending && errorMessage != null)
                Text(
                  errorMessage!,
                  style: TextStyle(fontSize: 12, color: AppColors.danger),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          const SizedBox(height: 10),
          _buildActions(scheme, interactive),
        ],
      ),
    );
  }

  String? _displayRejectionReason() {
    final reason = card.rejectionReason?.trim();
    if (reason == null || reason.isEmpty) return null;
    const groundedSourceReason =
        'non-advice change cards require at least one grounded source reference';
    if (reason.toLowerCase() == groundedSourceReason) {
      return '该建议缺少可校验依据，已被安全拦截，请重新生成。';
    }
    if (!_containsChinese(reason)) {
      return '该建议未通过安全校验，请重新生成。';
    }
    return reason;
  }

  bool _containsChinese(String text) =>
      RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

  Widget _buildActions(ColorScheme scheme, bool interactive) {
    if (status == ChangeCardStatus.applied) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: null,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.matchSoft,
            foregroundColor: AppColors.match,
          ),
          child: const Text('已应用', style: TextStyle(fontSize: 13)),
        ),
      );
    }
    if (status == ChangeCardStatus.declined) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onDecline,
          child: const Text('已忽略 · 撤销', style: TextStyle(fontSize: 13)),
        ),
      );
    }
    if (status == ChangeCardStatus.stale ||
        status == ChangeCardStatus.rejected) {
      return const SizedBox.shrink();
    }
    // pending
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: (interactive && !applying) ? onAccept : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.indigo,
              foregroundColor: Colors.white,
            ),
            child: applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('接受', style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: (interactive && !applying) ? onDecline : null,
          child: const Text('拒绝', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  IconData _typeIcon(ChangeCardType t) => switch (t) {
    ChangeCardType.moveTask => Icons.drag_handle_rounded,
    ChangeCardType.addTask => Icons.add_task_rounded,
    ChangeCardType.deleteTask => Icons.delete_outline,
    ChangeCardType.reschedulePhase => Icons.event_repeat_outlined,
    ChangeCardType.appendAdvice => Icons.lightbulb_outline,
  };

  ({String label, Color color}) _statusStyle(
    ChangeCardStatus s,
    ColorScheme scheme,
  ) => switch (s) {
    ChangeCardStatus.pending => (label: '待确认', color: AppColors.indigo),
    ChangeCardStatus.rejected => (label: '已驳回', color: AppColors.danger),
    ChangeCardStatus.applied => (label: '已应用', color: AppColors.match),
    ChangeCardStatus.declined => (label: '已忽略', color: AppColors.inkFaint),
    ChangeCardStatus.stale => (label: '已过期', color: AppColors.inkFaint),
  };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
