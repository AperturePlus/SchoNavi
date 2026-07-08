import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/di/providers.dart';
import '../../../core/error/app_exception.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../core/result/result.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/launcher/link_launcher.dart';
import '../../../domain/entities/favorite_item.dart';
import '../../../domain/entities/professor.dart';
import '../../../domain/entities/conversation_session.dart';
import '../../../domain/entities/feedback.dart';
import '../../../features/feedback/widgets/feedback_entry_button.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/field_chips.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../../shared/widgets/animated_entrance.dart';
import '../../../shared/widgets/bento_action_tile.dart';
import '../../../shared/widgets/bento_grid.dart';
import '../../../shared/widgets/bento_tile.dart';
import '../providers/professor_provider.dart';

class ProfessorPage extends ConsumerWidget {
  const ProfessorPage({
    super.key,
    required this.professorId,
    this.mainSessionId,
    this.sourceTurnId,
    this.forkId,
  });

  final String professorId;

  /// 从 fork 追问入口带来的主会话 id，供 Task 11 的 FAB 继续在该教授下追问使用。
  final String? mainSessionId;
  final String? sourceTurnId;
  final String? forkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(professorProvider(professorId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('导师详情'),
        actions: [
          FeedbackEntryButton(
            type: FeedbackType.missingProfessor,
            professorId: professorId,
            route: '/professor/$professorId',
          ),
        ],
      ),
      floatingActionButton: async.maybeWhen(
        data: (p) => FloatingActionButton.extended(
          onPressed: () => _openConversation(context, ref, p.id),
          icon: const Icon(Icons.chat_bubble_outline),
          label: Text(
            (forkId != null && forkId!.isNotEmpty) ||
                    (mainSessionId != null && sourceTurnId != null)
                ? '继续追问'
                : '咨询该导师',
          ),
        ),
        orElse: () => null,
      ),
      body: async.when(
        loading: () => const LoadingView(),
        error: (error, stackTrace) => ErrorView(
          error: normalizeAppException(error, stackTrace),
          onRetry: () => ref.invalidate(professorProvider(professorId)),
        ),
        data: (p) => _Detail(professor: p),
      ),
    );
  }

  Future<void> _openConversation(
    BuildContext context,
    WidgetRef ref,
    String professorId,
  ) async {
    if (forkId != null && forkId!.isNotEmpty) {
      context.push('/chat?sid=${Uri.encodeComponent(forkId!)}');
      return;
    }
    final repository = ref.read(conversationRepositoryProvider);
    final Result<ConversationSession> result;
    if (mainSessionId != null &&
        mainSessionId!.isNotEmpty &&
        sourceTurnId != null &&
        sourceTurnId!.isNotEmpty) {
      result = await repository.forkSessionAtTurn(
        sourceSessionId: mainSessionId!,
        sourceTurnId: sourceTurnId!,
        professorId: professorId,
      );
    } else {
      result = await repository.createSession(professorId: professorId);
    }
    if (!context.mounted) return;
    switch (result) {
      case Success<ConversationSession>(:final data):
        context.push('/chat?sid=${Uri.encodeComponent(data.id)}');
      case Failure<ConversationSession>(:final error):
        ref.read(apiErrorReporterProvider.notifier).report('创建导师会话失败', error);
    }
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.professor});

  final Professor professor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = professor;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isFavorite = ref
        .watch(favoriteStatusProvider(p.id))
        .maybeWhen(data: (value) => value, orElse: () => false);
    String orNa(String? v) => (v == null || v.isEmpty) ? '暂无信息' : v;

    Widget section(int index, {required String title, required Widget child}) {
      return AnimatedEntrance(
        index: index,
        child: BentoTile(
          color: scheme.surfaceContainerLowest,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AnimatedEntrance(
          index: 0,
          child: BentoTile(
            color: scheme.surfaceContainerLowest,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Hero(
                        tag: 'prof-name-${p.id}',
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            '${p.name}  ${p.title}',
                            style: textTheme.headlineSmall,
                          ),
                        ),
                      ),
                    ),
                    _FavoriteButton(
                      isFavorite: isFavorite,
                      onPressed: () {
                        Haptics.light();
                        ref
                            .read(favoriteRepositoryProvider)
                            .toggle(FavoriteItem.fromProfessor(p));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.university} / ${p.college}',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedEntrance(
          index: 1,
          child: BentoGrid(
            crossAxisCount: 2,
            spacing: 12,
            animateEntrance: false,
            children: [
              BentoActionTile(
                icon: Icons.mail_outline,
                label: '生成套磁邮件',
                onTap: () =>
                    context.push('/email?pid=${Uri.encodeComponent(p.id)}'),
              ),
              BentoActionTile(
                icon: Icons.insights_outlined,
                label: '匹配分析',
                onTap: () =>
                    context.push('/match?pid=${Uri.encodeComponent(p.id)}'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedEntrance(
          index: 2,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('AI 内容仅供准备参考，请自行核对事实。', style: textTheme.bodySmall),
          ),
        ),
        const SizedBox(height: 12),
        section(
          3,
          title: '主页',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(orNa(p.homepageUrl)),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openHomepage(context, ref, p.homepageUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('访问主页'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        section(
          4,
          title: '研究方向',
          child: FieldChips(fields: p.researchFields),
        ),
        const SizedBox(height: 12),
        section(5, title: '简介', child: Text(orNa(p.bio))),
        const SizedBox(height: 12),
        section(
          6,
          title: '数据来源',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(orNa(p.sourceUrl)),
              const SizedBox(height: 4),
              Text('更新时间：${orNa(p.updatedAt)}'),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openHomepage(
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
        messenger.showSnackBar(const SnackBar(content: Text('暂无主页信息')));
      case LaunchResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('主页可能已失效，可通过学校官网确认')),
        );
    }
  }
}

class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.isFavorite, required this.onPressed});

  final bool isFavorite;
  final VoidCallback onPressed;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: IconButton(
          tooltip: widget.isFavorite ? '取消收藏' : '收藏导师',
          icon: Icon(
            widget.isFavorite ? Icons.bookmark : Icons.bookmark_border,
          ),
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}
