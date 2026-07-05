import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/conversation_session.dart';
import '../../../domain/entities/search_history_item.dart';
import '../../../shared/widgets/empty_view.dart';
import '../../../shared/widgets/shimmer_skeleton.dart';
import '../../../shared/widgets/error_view.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _search
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationHistoryProvider);
    final legacy = ref.watch(searchHistoryProvider);
    final competitions =
        legacy.asData?.value
            .where((item) => item.type == SearchHistoryType.competition)
            .toList() ??
        const <SearchHistoryItem>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          if ((conversations.asData?.value.isNotEmpty ?? false) ||
              competitions.isNotEmpty)
            IconButton(
              tooltip: '清空历史',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: _clearAll,
            ),
        ],
      ),
      body: conversations.when(
        loading: () => const _LoadingList(),
        error: (error, stackTrace) => ErrorView(
          error: normalizeAppException(error, stackTrace),
          onRetry: () => ref.invalidate(conversationHistoryProvider),
        ),
        data: (sessions) {
          final query = _search.text.trim().toLowerCase();
          final filteredSessions = sessions.where((session) {
            if (query.isEmpty) return true;
            return (session.title ?? '导师咨询').toLowerCase().contains(query);
          }).toList();
          final filteredCompetitions = competitions.where((item) {
            if (query.isEmpty) return true;
            return item.prompt.toLowerCase().contains(query) ||
                item.summary.toLowerCase().contains(query);
          }).toList();
          if (sessions.isEmpty && competitions.isEmpty) {
            return const EmptyView(message: '暂无历史');
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: '搜索会话',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: _search.clear,
                          ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.indigo,
                  onRefresh: () async {
                    ref.invalidate(conversationHistoryProvider);
                    ref.invalidate(searchHistoryProvider);
                    await ref.read(conversationHistoryProvider.future);
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final session in filteredSessions)
                        _SessionTile(
                          key: ValueKey(session.id),
                          session: session,
                          onDeleted: () =>
                              ref.invalidate(conversationHistoryProvider),
                        ),
                      for (final competition in filteredCompetitions)
                        _CompetitionTile(
                          key: ValueKey('competition-${competition.sessionId}'),
                          item: competition,
                          onTap: () => context.push(
                            Uri(
                              path: '/home',
                              queryParameters: {
                                'tab': 'competition',
                                'historySid': competition.sessionId,
                              },
                            ).toString(),
                          ),
                          onDeleted: () =>
                              ref.invalidate(searchHistoryProvider),
                        ),
                      if (filteredSessions.isEmpty &&
                          filteredCompetitions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(child: Text('没有匹配的历史记录')),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('这会删除全部会话、分支和竞赛历史，且不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await ref
        .read(conversationRepositoryProvider)
        .clearSessions();
    if (result is Failure<void> && mounted) {
      ref
          .read(apiErrorReporterProvider.notifier)
          .report('清空会话历史失败', result.error);
      return;
    }
    try {
      await ref.read(historyRepositoryProvider).clear();
      ref.invalidate(conversationHistoryProvider);
      ref.invalidate(searchHistoryProvider);
    } catch (error, stackTrace) {
      if (!mounted) return;
      ref
          .read(apiErrorReporterProvider.notifier)
          .report('清空竞赛历史失败', error, stackTrace);
    }
  }
}

class _SessionTile extends ConsumerStatefulWidget {
  const _SessionTile({
    super.key,
    required this.session,
    required this.onDeleted,
  });

  final ConversationSession session;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_SessionTile> createState() => _SessionTileState();
}

class _SessionTileState extends ConsumerState<_SessionTile> {
  bool _expanded = false;
  bool _loading = false;
  List<ConversationSession> _forks = const [];

  Future<void> _toggle() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loading = true;
    });
    final result = await ref
        .read(conversationRepositoryProvider)
        .listForks(widget.session.rootSessionId);
    if (!mounted) return;
    switch (result) {
      case Success<List<ConversationSession>>(:final data):
        setState(() {
          _forks = data;
          _loading = false;
        });
      case Failure<List<ConversationSession>>(:final error):
        setState(() => _loading = false);
        ref.read(apiErrorReporterProvider.notifier).report('分支历史加载失败', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Card(
      child: Column(
        children: [
          Dismissible(
            key: ValueKey('root-${session.id}'),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _delete(session.id),
            background: _deleteBackground(context),
            child: ListTile(
              title: Text(session.title ?? _kindLabel(session.kind)),
              subtitle: Text(
                '${_kindLabel(session.kind)} · ${_formatDate(session.updatedAt)}',
              ),
              onTap: () =>
                  context.push('/chat?sid=${Uri.encodeComponent(session.id)}'),
              trailing: IconButton(
                tooltip: _expanded ? '收起分支' : '查看分支',
                icon: Icon(_expanded ? Icons.expand_less : Icons.account_tree),
                onPressed: _toggle,
              ),
            ),
          ),
          if (_expanded)
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_forks.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('暂无追问分支'),
                ),
              )
            else
              for (final fork in _forks)
                Dismissible(
                  key: ValueKey('fork-${fork.id}'),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _delete(fork.id, forkOnly: true),
                  background: _deleteBackground(context),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.subdirectory_arrow_right),
                    title: Text(_professorName(ref, fork.professorId)),
                    subtitle: Text(_formatDate(fork.updatedAt)),
                    onTap: () => context.push(
                      '/chat?sid=${Uri.encodeComponent(fork.id)}',
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Future<bool> _delete(String id, {bool forkOnly = false}) async {
    Haptics.medium();
    final result = await ref
        .read(conversationRepositoryProvider)
        .deleteSession(id);
    if (!mounted) return false;
    switch (result) {
      case Success<void>():
        if (forkOnly) {
          setState(() => _forks = _forks.where((f) => f.id != id).toList());
        } else {
          widget.onDeleted();
        }
        return true;
      case Failure<void>(:final error):
        ref.read(apiErrorReporterProvider.notifier).report('删除会话历史失败', error);
        return false;
    }
  }
}

class _CompetitionTile extends ConsumerWidget {
  const _CompetitionTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDeleted,
  });

  final SearchHistoryItem item;
  final VoidCallback onTap;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Dismissible(
    key: ValueKey(item.sessionId),
    direction: DismissDirection.endToStart,
    confirmDismiss: (_) async {
      try {
        await ref.read(historyRepositoryProvider).remove(item.sessionId);
        onDeleted();
        return true;
      } catch (error, stackTrace) {
        if (context.mounted) {
          ref
              .read(apiErrorReporterProvider.notifier)
              .report('删除竞赛历史失败', error, stackTrace);
        }
        return false;
      }
    },
    background: _deleteBackground(context),
    child: Card(
      child: ListTile(
        title: Text(item.prompt),
        subtitle: Text('竞赛 · ${item.summary}'),
        onTap: onTap,
      ),
    ),
  );
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.all(16),
    itemCount: 3,
    itemBuilder: (_, _) => const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: ShimmerSkeleton(height: 18, width: double.infinity),
      ),
    ),
  );
}

Widget _deleteBackground(BuildContext context) => Container(
  color: Theme.of(context).colorScheme.error,
  alignment: Alignment.centerRight,
  padding: const EdgeInsets.only(right: 20),
  child: const Icon(Icons.delete, color: Colors.white),
);

String _kindLabel(ConversationSessionKind kind) => switch (kind) {
  ConversationSessionKind.general => '导师推荐',
  ConversationSessionKind.professor => '导师咨询',
  ConversationSessionKind.fork => '追问分支',
};

String _professorName(WidgetRef ref, String? id) {
  if (id == null) return '导师追问';
  return ref.read(mockDbProvider).getProfessor(id)?.name ?? '导师追问';
}

String _formatDate(DateTime value) =>
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')} '
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
