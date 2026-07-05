import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/conversation_session.dart';
import '../../../domain/entities/search_history_item.dart';
import '../../../features/history/pages/history_page.dart';
import '../../../features/profile/providers/profile_provider.dart';

/// ChatGPT 风格的综合抽屉菜单。
///
/// 从屏幕右侧滑出，顶部展示个人档案入口，下方列出高频功能与最近记录。
/// 核心功能入口。
class AppMenuDrawer extends ConsumerWidget {
  const AppMenuDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(searchHistoryProvider);
    final conversationsAsync = ref.watch(conversationHistoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 顶部档案入口 ─────────────────────────────────────────────
            _ProfileHeader(
              onTap: () async {
                final router = GoRouter.of(context);
                final navigator = Navigator.of(context);
                final profileFuture = ref
                    .read(profileProvider.notifier)
                    .ensureLoadedForProfileGate();
                final store = ref.read(localStoreProvider);

                navigator.pop();

                final profile = await profileFuture;
                final agreed = store.getBool('privacy_agreed') ?? false;
                final target = profile == null || !profile.isEmpty
                    ? '/profile'
                    : (agreed ? '/profile/intro' : '/profile/privacy');
                router.push(target);
              },
            ),
            Divider(height: 1, color: scheme.outline),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.history,
                      label: '历史',
                      onTap: () => _navigate(context, '/history'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.bookmark_outline,
                      label: '我的收藏',
                      onTap: () => _navigate(context, '/favorites'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuickActionButton(
                      icon: Icons.flag_outlined,
                      label: '我的备赛',
                      onTap: () => _navigate(context, '/preparation-plans'),
                    ),
                  ),
                ],
              ),
            ),

            Divider(height: 1, color: scheme.outline),

            // ── 最近：导师/教授会话（对话库）+ 竞赛搜索史 ────────────────
            Expanded(
              child: _buildRecent(context, historyAsync, conversationsAsync),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecent(
    BuildContext context,
    AsyncValue<List<SearchHistoryItem>> historyAsync,
    AsyncValue<List<ConversationSession>> conversationsAsync,
  ) {
    // 会话列表失败不阻塞竞赛历史展示，按空处理。
    if (conversationsAsync.isLoading && !conversationsAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (historyAsync.isLoading && !historyAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }

    final sessions = conversationsAsync.asData?.value ?? const [];
    final competitions = (historyAsync.asData?.value ?? const [])
        .where((item) => item.type == SearchHistoryType.competition)
        .toList(growable: false);

    final entries = <_RecentEntry>[
      ...sessions.map(_RecentEntry.fromSession),
      ...competitions.map(_RecentEntry.fromCompetition),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (entries.isEmpty) {
      return _EmptyHint(icon: Icons.manage_search_outlined, message: '暂无最近会话');
    }
    return _RecentSearchPanel(
      entries: entries,
      onTap: (entry) {
        Haptics.light();
        Navigator.of(context).pop();
        context.push(entry.route);
      },
    );
  }

  void _navigate(BuildContext context, String route) {
    Haptics.light();
    Navigator.of(context).pop();
    context.push(route);
  }
}

// ── Profile header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.indigoSoftOf(isDark),
              child: Icon(Icons.person, color: AppColors.indigo, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '我的档案',
                    style: textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '查看并编辑个人信息',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Quick actions ────────────────────────────────────────────────────────────

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: scheme.onSurfaceVariant, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Recent entry model + local filtering ────────────────────────────────────

/// 抽屉「最近」统一条目：导师/教授会话或竞赛搜索史映射到同一模型。
class _RecentEntry {
  const _RecentEntry({
    required this.id,
    required this.title,
    required this.typeLabel,
    required this.icon,
    required this.timestamp,
    required this.route,
  });

  factory _RecentEntry.fromSession(ConversationSession session) {
    final label = switch (session.kind) {
      ConversationSessionKind.general => '导师推荐',
      ConversationSessionKind.professor => '导师咨询',
      ConversationSessionKind.fork => '追问分支',
    };
    return _RecentEntry(
      id: 'session-${session.id}',
      title: session.title ?? label,
      typeLabel: label,
      icon: Icons.chat_bubble_outline,
      timestamp: session.updatedAt,
      route: '/chat?sid=${Uri.encodeComponent(session.id)}',
    );
  }

  factory _RecentEntry.fromCompetition(SearchHistoryItem item) {
    return _RecentEntry(
      id: 'competition-${item.sessionId}',
      title: item.prompt,
      typeLabel: '竞赛',
      icon: Icons.emoji_events_outlined,
      timestamp: item.createdAt,
      route: '/home?tab=competition',
    );
  }

  final String id;
  final String title;
  final String typeLabel;
  final IconData icon;
  final DateTime timestamp;
  final String route;

  bool matches(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        typeLabel.toLowerCase().contains(q);
  }
}

class _RecentSearchPanel extends StatefulWidget {
  const _RecentSearchPanel({required this.entries, required this.onTap});

  final List<_RecentEntry> entries;
  final ValueChanged<_RecentEntry> onTap;

  @override
  State<_RecentSearchPanel> createState() => _RecentSearchPanelState();
}

class _RecentSearchPanelState extends State<_RecentSearchPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _query = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<_RecentEntry> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.entries;
    return widget.entries.where((entry) => entry.matches(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 4),
          child: Row(
            children: [
              Text(
                '最近',
                style: textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    style: textTheme.bodySmall,
                    decoration: InputDecoration(
                      hintText: '搜索',
                      hintStyle: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 34,
                        minHeight: 32,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _searchController.clear,
                            ),
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      isDense: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyHint(
                  icon: Icons.manage_search_outlined,
                  message: '没有匹配的最近搜索',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  itemCount: filtered.length.clamp(0, 8),
                  itemBuilder: (context, index) {
                    final entry = filtered[index];
                    return _HistoryTile(
                      entry: entry,
                      onTap: () => widget.onTap(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── History preview tile ─────────────────────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final _RecentEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(entry.icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Empty hint ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
