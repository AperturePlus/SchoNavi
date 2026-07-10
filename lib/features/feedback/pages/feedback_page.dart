import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/feedback.dart';
import '../../../shared/widgets/error_view.dart';
import '../providers/feedback_provider.dart';

class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key, this.type, this.context});

  final FeedbackType? type;
  final FeedbackContext? context;

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  late FeedbackType _type = widget.type ?? FeedbackType.other;
  final TextEditingController _content = TextEditingController();
  final TextEditingController _contact = TextEditingController();

  @override
  void initState() {
    super.initState();
    _content.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _content.dispose();
    _contact.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _content.text.trim().length >= 5 &&
      !ref.read(feedbackSubmitProvider).loading;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    Haptics.medium();
    final cfg = ref.read(appConfigProvider);
    final ctx = (widget.context ?? const FeedbackContext()).copyWith(
      appVersion: cfg.appVersion,
      dataSourceMode: 'http',
    );
    final ok = await ref
        .read(feedbackSubmitProvider.notifier)
        .submit(
          type: _type,
          content: _content.text.trim(),
          contact: _contact.text.trim().isEmpty ? null : _contact.text.trim(),
          context: ctx,
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(const SnackBar(content: Text('感谢反馈,我们会尽快处理')));
      context.pop();
    } else {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(feedbackSubmitProvider);
    final ctx = widget.context ?? const FeedbackContext();
    return Scaffold(
      appBar: AppBar(title: const Text('反馈')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TypeSelector(
                selected: _type,
                onChanged: (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _content,
                maxLength: 500,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '描述',
                  hintText: '请描述你遇到的问题或建议(至少 5 个字)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: '联系方式(可选)',
                  hintText: '手机 / 邮箱 / 微信号,方便我们追问',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (!ctx.isEmpty) _ContextSummary(context: ctx),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                ErrorView(error: state.error),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: (state.loading || !_canSubmit) ? null : _submit,
                child: state.loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('提交'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});

  final FeedbackType selected;
  final ValueChanged<FeedbackType> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      (FeedbackType.bug, 'Bug / 异常'),
      (FeedbackType.recommendation, '推荐不准'),
      (FeedbackType.missingProfessor, '导师未收录'),
      (FeedbackType.other, '其他建议'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            label: Text(item.$2),
            selected: selected == item.$1,
            onSelected: (_) {
              Haptics.selection();
              onChanged(item.$1);
            },
          ),
      ],
    );
  }
}

class _ContextSummary extends StatelessWidget {
  const _ContextSummary({required this.context});
  final FeedbackContext context;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (this.context.route != null) '页面 ${this.context.route}',
      if (this.context.professorId != null) '导师 ${this.context.professorId}',
      if (this.context.competitionId != null)
        '竞赛 ${this.context.competitionId}',
      if (this.context.sessionId != null) '会话 ${this.context.sessionId}',
      if (this.context.messageId != null) '消息 ${this.context.messageId}',
      if (this.context.prompt != null) '提问 ${this.context.prompt}',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已附加:${parts.join(" / ")}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
