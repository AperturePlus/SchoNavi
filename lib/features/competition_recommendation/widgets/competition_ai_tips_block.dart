import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/recommended_competition.dart';
import '../../../shared/widgets/bento_tile.dart';

class CompetitionAiTipsBlock extends StatelessWidget {
  const CompetitionAiTipsBlock({super.key, required this.competition});
  final RecommendedCompetition competition;

  @override
  Widget build(BuildContext context) {
    final tips = competition.preparationTips;
    final limits = competition.limitations;
    if (tips.isEmpty && limits.isEmpty) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return BentoTile(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.indigo),
              const SizedBox(width: 8),
              Text('AI 补充提示', style: textTheme.titleMedium),
            ],
          ),
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('备赛建议', style: textTheme.labelLarge),
            ...tips.map(
              (x) => GptMarkdown(
                '· $x',
                style: textTheme.bodySmall?.copyWith(height: 1.55),
              ),
            ),
          ],
          if (limits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('注意事项', style: textTheme.labelLarge),
            ...limits.map(
              (x) => GptMarkdown(
                '· $x',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
