import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/competition.dart';
import '../../../domain/entities/research_item.dart';
import '../../../domain/entities/user_profile.dart';
import '../../../domain/repositories/profile_extraction_repository.dart';
import '../providers/achievements_extraction_provider.dart';
import 'achievement_item_card.dart';

class AchievementsEditor extends ConsumerStatefulWidget {
  const AchievementsEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final UserProfile value;
  final ValueChanged<UserProfile> onChanged;

  @override
  ConsumerState<AchievementsEditor> createState() => _AchievementsEditorState();
}

class _AchievementsEditorState extends ConsumerState<AchievementsEditor> {
  final TextEditingController _raw = TextEditingController();

  @override
  void dispose() {
    _raw.dispose();
    super.dispose();
  }

  void _mergeDraft(AchievementDraft draft) {
    Haptics.success();
    widget.onChanged(
      widget.value.copyWith(
        competitions: [...widget.value.competitions, ...draft.competitions],
        research: [...widget.value.research, ...draft.research],
      ),
    );
    ref.read(achievementsExtractionProvider.notifier).reset();
    _raw.clear();
  }

  void _removeCompetition(int i) {
    final next = [...widget.value.competitions]..removeAt(i);
    widget.onChanged(widget.value.copyWith(competitions: next));
  }

  void _removeResearch(int i) {
    final next = [...widget.value.research]..removeAt(i);
    widget.onChanged(widget.value.copyWith(research: next));
  }

  @override
  Widget build(BuildContext context) {
    final extraction = ref.watch(achievementsExtractionProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen(achievementsExtractionProvider, (prev, next) {
      final draft = next.value;
      if (draft != null) _mergeDraft(draft);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('achievements-raw'),
          controller: _raw,
          maxLines: 4,
          decoration: InputDecoration(
            hintText:
                '粘贴/输入你的竞赛、论文、项目、专利等经历，如：'
                'ACM 区域赛银牌；一篇 EI 一作论文…',
            filled: true,
            fillColor: scheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 10),
        if (extraction.isLoading)
          FilledButton.icon(
            onPressed: null,
            icon: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            label: const Text('AI 正在整理'),
          )
        else
          FilledButton.icon(
            onPressed: () {
              final text = _raw.text.trim();
              if (text.isEmpty) return;
              Haptics.medium();
              ref.read(achievementsExtractionProvider.notifier).extract(text);
            },
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 整理成条目'),
          ),
        if (extraction.hasError)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '整理失败，请重试或手动添加',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        const SizedBox(height: 16),
        _Header(label: '竞赛成果', onAdd: () => _showCompetitionDialog()),
        for (var i = 0; i < widget.value.competitions.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AchievementItemCard(
              icon: Icons.emoji_events_outlined,
              title: widget.value.competitions[i].name,
              subtitle: _competitionSubtitle(widget.value.competitions[i]),
              onDelete: () => _removeCompetition(i),
            ),
          ),
        const SizedBox(height: 12),
        _Header(label: '科研成果', onAdd: () => _showResearchDialog()),
        for (var i = 0; i < widget.value.research.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AchievementItemCard(
              icon: Icons.article_outlined,
              title: widget.value.research[i].title,
              subtitle: _researchSubtitle(widget.value.research[i]),
              onDelete: () => _removeResearch(i),
            ),
          ),
      ],
    );
  }

  String _competitionSubtitle(Competition c) => [
    c.level,
    c.award,
    c.year,
  ].where((e) => e != null && e.isNotEmpty).join(' · ');

  String _researchSubtitle(ResearchItem r) => [
    r.role,
    r.venueOrStatus,
    r.year,
  ].where((e) => e != null && e.isNotEmpty).join(' · ');

  Future<void> _showCompetitionDialog() async {
    final name = TextEditingController();
    final award = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加竞赛'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            TextField(
              controller: award,
              decoration: const InputDecoration(labelText: '奖项（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      widget.onChanged(
        widget.value.copyWith(
          competitions: [
            ...widget.value.competitions,
            Competition(
              name: name.text.trim(),
              award: award.text.trim().isEmpty ? null : award.text.trim(),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showResearchDialog() async {
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加科研成果'),
        content: TextField(
          controller: title,
          decoration: const InputDecoration(labelText: '标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      widget.onChanged(
        widget.value.copyWith(
          research: [
            ...widget.value.research,
            ResearchItem(type: ResearchType.other, title: title.text.trim()),
          ],
        ),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.label, required this.onAdd});
  final String label;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
      const Spacer(),
      TextButton.icon(
        onPressed: onAdd,
        icon: const Icon(Icons.add, size: 16),
        label: const Text('手动添加'),
      ),
    ],
  );
}
