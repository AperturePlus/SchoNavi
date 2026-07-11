import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/platform/system_share_platform.dart';
import '../../../domain/entities/competition_recommendation_result.dart';
import '../../../domain/entities/recommended_competition.dart';
import '../../../shared/widgets/recommendation_card_data.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/swipe_card_carousel.dart';
import '../../../shared/widgets/swipe_recommendation_card.dart';
import '../../../shared/utils/share_text_builder.dart';
import '../mappers/competition_card_mapper.dart';
import '../providers/competition_home_notifier.dart';
import 'competition_query_understanding_card.dart';

/// 首页原地结果视图：把 [CompetitionHomeState] 渲染为输入区下方的结果区域。
///
/// - idle：空占位
/// - loading：用户气泡 + 正在思考占位
/// - result：用户气泡 + 助手摘要 + 需求理解卡 + 横滑推荐卡 + 调整条件按钮
/// - historySummary：用户气泡 + 历史摘要 + 重新生成按钮
/// - empty：用户气泡 + 空提示 + 调整条件按钮
/// - error：用户气泡 + 错误文案 + 重试按钮
class CompetitionHomeResultView extends ConsumerWidget {
  const CompetitionHomeResultView({
    super.key,
    required this.state,
    required this.onAdjust,
    required this.onRetry,
    this.prompt,
    this.onOpenDetail,
    this.onOpenUrl,
  });

  final CompetitionHomeState state;
  final VoidCallback onAdjust;
  final Future<void> Function(String prompt) onRetry;

  /// 父层传入的原始 prompt。
  ///
  /// 用于 result / empty / error 下落稳态渲染用户消息气泡；loading 取用
  /// [CompetitionHomeLoading.prompt]。
  final String? prompt;

  /// 点击竞赛卡片时回调竞赛 id；由外层负责路由跳转。
  final void Function(String competitionId)? onOpenDetail;

  /// 点击卡片「访问官网」时回调官方 URL；由外层负责实际打开（例如 linkLauncher）。
  /// 仅当卡片 [RecommendationCardData.openUrl] 与本回调均非空时才挂载按钮。
  final void Function(String url)? onOpenUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state) {
      CompetitionHomeIdle() => const SizedBox.shrink(),
      CompetitionHomeLoading(:final prompt) => _buildLoading(context, prompt),
      CompetitionHomeResult(:final data) => _buildResult(context, ref, data),
      CompetitionHomeHistorySummary(:final summary) => _buildHistorySummary(
        context,
        summary,
      ),
      CompetitionHomeEmpty() => _buildEmpty(context),
      CompetitionHomeError(:final error) => _buildError(context, error),
    };
  }

  Widget _buildLoading(BuildContext context, String prompt) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserMessageBubble(text: prompt),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: AppColors.indigo),
              const SizedBox(width: 8),
              Text(
                '正在为你匹配竞赛…',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResult(
    BuildContext context,
    WidgetRef ref,
    CompetitionRecommendationResult data,
  ) {
    final recs = data.recommendations;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserMessageBubble(text: prompt),
          const SizedBox(height: 16),
          _buildSummary(context, data),
          const SizedBox(height: 16),
          CompetitionQueryUnderstandingCard(understanding: data.understanding),
          const SizedBox(height: 16),
          SwipeCardCarousel<RecommendationCardData>(
            height: 260,
            items: recs.map((c) => c.toCardData()).toList(growable: false),
            semanticsLabel: (d) => d.title,
            itemBuilder: (context, cardData, index) {
              final openUrl = cardData.openUrl;
              final urlLauncher = (openUrl == null || onOpenUrl == null)
                  ? null
                  : () => onOpenUrl!(openUrl);
              return SwipeRecommendationCard(
                data: cardData,
                onTap: () => onOpenDetail?.call(cardData.id),
                onOpenUrlPressed: urlLauncher,
                onSharePressed: ref.read(systemSharePlatformProvider).isSupported
                    ? () => _shareCompetition(context, ref, recs[index])
                    : null,
              );
            },
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
              onPressed: onAdjust,
              child: const Text('调整条件'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareCompetition(
    BuildContext context,
    WidgetRef ref,
    RecommendedCompetition competition,
  ) async {
    final result = await ref
        .read(systemSharePlatformProvider)
        .shareText(ShareTextBuilder.competition(competition));
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

  Widget _buildSummary(
    BuildContext context,
    CompetitionRecommendationResult data,
  ) {
    final u = data.understanding;
    final directions = u.directions.isEmpty ? null : u.directions.join('、');
    final categories = u.categories.isEmpty ? null : u.categories.join('、');
    final buffer = StringBuffer('我理解了');
    if (directions != null) {
      buffer.write('你对「$directions」方向');
    }
    if (categories != null) {
      buffer.write('${directions != null ? '的' : ''}$categories类竞赛');
    }
    if (directions == null && categories == null) {
      buffer.write('你的竞赛需求');
    }
    buffer.write('，为你推荐以下竞赛：');
    return Text(
      buffer.toString(),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserMessageBubble(text: prompt),
          const SizedBox(height: 16),
          Text(
            '暂无匹配竞赛，试试调整条件',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAdjust, child: const Text('调整条件')),
        ],
      ),
    );
  }

  Widget _buildHistorySummary(BuildContext context, String summary) {
    final scheme = Theme.of(context).colorScheme;
    final retryPrompt = prompt;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserMessageBubble(text: prompt),
          const SizedBox(height: 16),
          Text('这是当时保存的竞赛历史摘要：', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(
            summary,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (retryPrompt != null && retryPrompt.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onRetry(retryPrompt),
              child: const Text('重新生成'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, AppException error) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _UserMessageBubble(text: prompt),
          const SizedBox(height: 16),
          ErrorView(
            error: error,
            onRetry: () {
              final retryPrompt = prompt;
              if (retryPrompt != null) onRetry(retryPrompt);
            },
          ),
        ],
      ),
    );
  }
}

/// 简化的右对齐用户消息气泡，使用应用统一的 indigoSoft 底色。
class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final content = text;
    if (content == null || content.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width * 0.78;
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.indigoSoftOf(isDark),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(content, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ),
    );
  }
}
