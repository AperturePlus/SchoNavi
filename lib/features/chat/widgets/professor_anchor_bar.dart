import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/fork_ref.dart';

/// fork 追问页顶部常驻的教授锚点条（方案 A，sticky）。
///
/// 仅在 [ChatState.forkAnchor] 非 null 时渲染。点击条身回详情页。
///
/// 可选 [leading] / [trailing] 槽位把 fork 追问页的「返回」「重新生成」
/// 悬浮按钮收进条内同一行，避免它们作为独立 `Positioned` 与本条在顶部
/// 重叠（详见 chat_page Stack 布局）。两者均 null 时退化为纯展示条，
/// 既有调用与测试不受影响。
class ProfessorAnchorBar extends StatelessWidget {
  const ProfessorAnchorBar({
    super.key,
    required this.anchor,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final ForkRef anchor;
  final VoidCallback onTap;

  /// 条身左侧操作位（fork 追问页放「返回」）。null 则仅留默认起始 padding。
  final Widget? leading;

  /// 条身右侧操作位（fork 追问页放「重新生成」）。null 则仅留默认结束 padding。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = anchor.professorName == forkProfessorUnavailableLabel
        ? anchor.professorName
        : '${anchor.professorName} 教授';
    final subtitle = anchor.college == null || anchor.college!.isEmpty
        ? anchor.university
        : '${anchor.university} · ${anchor.college}';
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.indigo,
                child: Text(
                  anchor.avatarLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall,
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '追问中',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.indigo,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
