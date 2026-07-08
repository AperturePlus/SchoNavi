import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/recommended_competition.dart';
import '../../../shared/widgets/bento_tile.dart';

class CompetitionFactBlock extends StatelessWidget {
  const CompetitionFactBlock({super.key, required this.competition});
  final RecommendedCompetition competition;

  @override
  Widget build(BuildContext context) {
    final c = competition;
    return BentoTile(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('赛制信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _KVRow(label: '报名时间', value: c.signupTime),
          _KVRow(label: '比赛时间', value: c.contestTime),
          _KVRow(label: '团队规模', value: c.teamSize),
          _KVRow(label: '形式', value: c.format),
          _KVRow(label: '主办方', value: c.organizer),
        ],
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  const _KVRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final isEmpty = value.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEmpty
                ? Text(
                    '暂无信息',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.faintOf(isDark),
                    ),
                  )
                : GptMarkdown(
                    value,
                    style: textTheme.bodySmall?.copyWith(height: 1.55),
                  ),
          ),
        ],
      ),
    );
  }
}
