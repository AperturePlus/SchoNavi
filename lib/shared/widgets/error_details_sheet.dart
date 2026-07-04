import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/error/app_exception.dart';

bool apiErrorDetailsEnabled(BuildContext context) {
  try {
    return ProviderScope.containerOf(context).read(
      appConfigProvider.select(
        (config) => config.featureFlags.showApiErrorDetails,
      ),
    );
  } on StateError {
    return false;
  }
}

Future<void> showErrorDetailsSheet(
  BuildContext context,
  AppException error,
) async {
  final details = error.diagnostics;
  if (details == null || details.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (context) => _ErrorDetailsSheet(error: error),
  );
}

class _ErrorDetailsSheet extends StatelessWidget {
  const _ErrorDetailsSheet({required this.error});

  final AppException error;

  @override
  Widget build(BuildContext context) {
    final details = error.diagnostics!;
    final rows = <(String, String?)>[
      ('请求 ID', details.requestId),
      ('请求方法', details.method),
      ('接口路径', details.path),
      ('HTTP 状态', details.httpStatus?.toString()),
      ('业务码', details.backendCode),
      ('后端消息', details.backendMessage),
      ('异常类型', details.exceptionType),
      ('异常原因', details.cause),
      ('发生时间', details.occurredAt?.toIso8601String()),
      ...details.context.entries.map((entry) => (entry.key, entry.value)),
      ('响应预览', details.responsePreview),
      ('堆栈', details.stackTrace),
    ];
    final visibleRows = rows
        .where((row) => row.$2 != null && row.$2!.trim().isNotEmpty)
        .toList(growable: false);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, controller) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '联调错误详情',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(error.message, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: controller,
                itemCount: visibleRows.length,
                separatorBuilder: (_, _) => const Divider(height: 20),
                itemBuilder: (context, index) {
                  final row = visibleRows[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.$1,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        row.$2!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: details.format(message: error.message)),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('错误详情已复制')));
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制全部详情'),
            ),
          ],
        ),
      ),
    );
  }
}
