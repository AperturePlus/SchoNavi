import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/competition_query_understanding.dart';
import '../../../domain/services/competition_query_understanding_normalizer.dart';
import '../../../shared/widgets/bento_tile.dart';

/// 「我理解到的需求」卡：冷调玻璃拟态 BentoTile + AI 图标头 + 结构化键值网格。
///
/// 将裸 Card 升级为 Bento 体系，标题行加 auto_awesome 图标暗示「AI 正在理解你」；
/// 四行纯文本改为键值行（键 inkSoft / 值 ink / 空值 inkFaint 弱化），便于扫读。
/// 待确认项保留 `· x` 纯文本（不升级为警示胶囊）。
class CompetitionQueryUnderstandingCard extends StatelessWidget {
  const CompetitionQueryUnderstandingCard({
    super.key,
    required this.understanding,
  });

  final CompetitionQueryUnderstanding understanding;

  @override
  Widget build(BuildContext context) {
    final u = CompetitionQueryUnderstandingNormalizer.normalize(understanding);
    final textTheme = Theme.of(context).textTheme;

    String join(List<String> xs) => xs.isEmpty ? '暂无信息' : xs.join('、');

    return BentoTile(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.indigo),
              const SizedBox(width: 8),
              Text('我理解到的需求', style: textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          _KVRow(label: '方向', value: join(u.directions)),
          _KVRow(label: '类别', value: join(u.categories)),
          _KVRow(label: '时间', value: join(u.timingPreferences)),
          _KVRow(label: '组队', value: join(u.teamPreferences)),
          if (u.uncertainties.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('待确认：', style: textTheme.labelLarge),
            ...u.uncertainties.map(
              (x) => Text(
                '· $x',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 键值行：左侧固定宽标签 + 右侧值，baseline 对齐。
/// 空值（「暂无信息」）用 inkFaint 弱化，避免与有值行同等权重。
class _KVRow extends StatelessWidget {
  const _KVRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final isEmpty = value == '暂无信息';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.ideographic,
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
            child: Text(
              value,
              style: textTheme.bodySmall?.copyWith(
                color: isEmpty ? AppColors.faintOf(isDark) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
