import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/ui/app_bottom_sheet.dart';
import '../../../domain/entities/user_profile.dart';
import '../../../shared/widgets/animated_entrance.dart';
import '../providers/profile_provider.dart';
import '../widgets/achievements_editor.dart';
import '../widgets/basic_info_form.dart';
import '../widgets/profile_section_tile.dart';
import '../widgets/profile_summary_header.dart';
import '../widgets/score_and_interests_form.dart';

/// 档案中心：完成度头 + 分区卡（点开聚焦编辑，复用向导 organism）。
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectIfProfileMissing();
    });
  }

  Future<void> _redirectIfProfileMissing() async {
    if (!mounted || _redirected) return;
    final profile = await ref
        .read(profileProvider.notifier)
        .ensureLoadedForProfileGate();
    if (!mounted || _redirected || profile == null || !profile.isEmpty) return;

    _redirected = true;
    final store = ref.read(localStoreProvider);
    final agreed = store.getBool('privacy_agreed') ?? false;
    if (!agreed) {
      context.push('/profile/privacy');
    } else {
      context.push('/profile/intro');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final isHttp = ref.watch(
      appConfigProvider.select((cfg) => cfg.dataSource == DataSource.http),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('我的档案')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          AnimatedEntrance(
            index: 0,
            child: ProfileSummaryHeader(
              profile: profile,
              onUseForReco: () => context.go('/home'),
            ),
          ),
          const SizedBox(height: 16),
          AnimatedEntrance(
            index: 1,
            child: ProfileSectionTile(
              title: '基本信息',
              summary: profile.name ?? '待填写',
              done: profile.name != null && profile.gender != null,
              onTap: () => _editBasic(context, profile),
            ),
          ),
          AnimatedEntrance(
            index: 2,
            child: ProfileSectionTile(
              title: '成绩 & 方向',
              summary: profile.score?.gpa != null
                  ? 'GPA ${profile.score!.gpa}'
                  : '待填写',
              done: profile.score?.gpa != null,
              onTap: () => _editScore(context, profile),
            ),
          ),
          AnimatedEntrance(
            index: 3,
            child: ProfileSectionTile(
              title: '竞赛成果',
              summary: '${profile.competitions.length} 项',
              done: profile.competitions.isNotEmpty,
              onTap: () => _editAchievements(context, profile),
            ),
          ),
          AnimatedEntrance(
            index: 4,
            child: ProfileSectionTile(
              title: '科研成果',
              summary: '${profile.research.length} 项',
              done: profile.research.isNotEmpty,
              onTap: () => _editAchievements(context, profile),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedEntrance(
            index: 5,
            child: Column(
              children: [
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _FooterLink(
                      label: '隐私协议',
                      onTap: () => context.push('/profile/privacy'),
                    ),
                    Text(
                      ' · ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    _FooterLink(
                      label: '数据如何使用',
                      onTap: () => _showDataUsage(context, isHttp: isHttp),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'SchoNavi v1.0.0',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBasic(BuildContext context, UserProfile p) => _editSheet(
    context,
    p,
    (draft, onChanged) => BasicInfoForm(value: draft, onChanged: onChanged),
  );

  Future<void> _editScore(BuildContext context, UserProfile p) => _editSheet(
    context,
    p,
    (draft, onChanged) =>
        ScoreAndInterestsForm(value: draft, onChanged: onChanged),
  );

  Future<void> _editAchievements(BuildContext context, UserProfile p) =>
      _editSheet(
        context,
        p,
        (draft, onChanged) =>
            AchievementsEditor(value: draft, onChanged: onChanged),
      );

  Future<void> _editSheet(
    BuildContext context,
    UserProfile initial,
    Widget Function(UserProfile draft, ValueChanged<UserProfile> onChanged)
    builder,
  ) async {
    var draft = initial;
    await showAppBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                builder(draft, (p) => setState(() => draft = p)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('保存'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    await ref.read(profileProvider.notifier).save(draft);
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
                decorationColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.open_in_new,
              size: 12,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

void _showDataUsage(BuildContext context, {required bool isHttp}) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('数据如何使用'),
      content: Text(
        isHttp
            ? '真实后端模式下，你的个人档案会同步到后端，用于：\n\n'
                  '• 个性化导师推荐\n'
                  '• 生成 outreach 邮件\n'
                  '• 匹配度分析\n\n'
                  '你随时可以在「我的档案」中修改，或在「设置」中删除远端资料。'
            : '你的个人档案仅保存在本机，用于：\n\n'
                  '• 个性化导师推荐\n'
                  '• 生成 outreach 邮件\n'
                  '• 匹配度分析\n\n'
                  'LLM 模式下，档案信息会随请求发送给大模型用于解析。'
                  '你随时可以在「我的档案」中修改或删除数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}
