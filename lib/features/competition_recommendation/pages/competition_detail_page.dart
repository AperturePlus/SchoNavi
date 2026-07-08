import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/launcher/link_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/match_level.dart';
import '../../../domain/entities/recommended_competition.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../../../shared/widgets/match_level_chip.dart';
import '../../../shared/widgets/error_view.dart';
import '../../preparation/providers/preparation_providers.dart';
import '../widgets/competition_ai_tips_block.dart';
import '../widgets/competition_fact_block.dart';

class CompetitionDetailPage extends ConsumerWidget {
  const CompetitionDetailPage({
    super.key,
    required this.competitionId,
    this.recommended,
  });

  final String competitionId;
  final RecommendedCompetition? recommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final baseAsync = ref.watch(competitionByIdProvider(competitionId));
    return baseAsync.when(
      data: (base) {
        if (base == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('竞赛详情')),
            body: Center(
              child: Text(
                '未找到该竞赛',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }
        return _CompetitionDetailBody(
          competitionId: competitionId,
          base: base,
          recommended: recommended,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('竞赛详情')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('竞赛详情')),
        body: ErrorView(
          error: normalizeAppException(error, stackTrace),
          onRetry: () => ref.invalidate(competitionByIdProvider(competitionId)),
        ),
      ),
    );
  }
}

class _CompetitionDetailBody extends ConsumerWidget {
  const _CompetitionDetailBody({
    required this.competitionId,
    required this.base,
    required this.recommended,
  });

  final String competitionId;
  final RecommendedCompetition base;
  final RecommendedCompetition? recommended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 目录事实优先；recommended 仅补 AI 字段与匹配度。
    final merged = recommended == null
        ? base
        : base.copyWith(
            limitations: recommended!.limitations,
            preparationTips: recommended!.preparationTips,
            matchScore: recommended!.matchScore,
            reason: recommended!.reason,
          );

    final active = ref.watch(activePlanForCompetitionProvider(competitionId));

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(merged.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          BentoTile(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            merged.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${merged.category} / ${merged.level}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 仅在 recommended 传入真实 matchScore 时展示匹配度胶囊；
                    // 目录直入（深链/历史）matchScore 为 0，展示「0%」会误导。
                    if (recommended != null) ...[
                      const SizedBox(width: 8),
                      MatchLevelChip(
                        level: MatchLevel.fromScore(merged.matchScore),
                        matchScore: merged.matchScore,
                      ),
                    ],
                  ],
                ),
                if (merged.reason.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GptMarkdown(
                    merged.reason,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          CompetitionFactBlock(competition: merged),
          const SizedBox(height: 12),
          CompetitionAiTipsBlock(competition: merged),
          const SizedBox(height: 16),
          if (merged.officialUrl != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.cyan,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _openOfficial(context, ref, merged.officialUrl),
              icon: const Icon(Icons.open_in_new),
              label: const Text('访问官网'),
            ),
          // 备赛按钮：有进行中计划→"继续备赛"跳详情；无→"开始备赛"跳表单。
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.indigo,
            ),
            onPressed: () {
              if (active != null) {
                context.push('/preparation-plans/${active.id}');
              } else {
                context.push(
                  '/preparation-plans/new?competitionId=$competitionId',
                );
              }
            },
            icon: const Icon(Icons.flag_outlined),
            label: Text(active != null ? '继续备赛' : '开始备赛'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOfficial(
    BuildContext context,
    WidgetRef ref,
    String? url,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(linkLauncherProvider).open(url);
    switch (result) {
      case LaunchResult.success:
        return;
      case LaunchResult.noUrl:
        messenger.showSnackBar(
          const SnackBar(content: Text('暂无官网信息，请以学校或赛事官方通知为准')),
        );
      case LaunchResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('官网可能暂时无法打开，请以赛事官方通知为准')),
        );
    }
  }
}
