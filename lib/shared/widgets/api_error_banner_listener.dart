import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/error/api_error_reporter.dart';
import 'error_details_sheet.dart';

class ApiErrorBannerListener extends ConsumerWidget {
  const ApiErrorBannerListener({
    super.key,
    required this.child,
    this.scaffoldMessengerKey,
    this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ReportedAppError?>(apiErrorReporterProvider, (_, next) {
      final messenger =
          scaffoldMessengerKey?.currentState ??
          ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.clearMaterialBanners();
      if (next == null) return;

      final showDetails = ref.read(
        appConfigProvider.select(
          (config) => config.featureFlags.showApiErrorDetails,
        ),
      );
      final requestId = next.error.diagnostics?.requestId;
      messenger.showMaterialBanner(
        MaterialBanner(
          leading: const Icon(Icons.warning_amber_rounded),
          content: Semantics(
            liveRegion: true,
            label: '${next.source}失败：${next.error.message}',
            child: Text(
              '${next.source}：${next.error.message}'
              '${requestId == null ? '' : '\n错误编号：$requestId'}',
            ),
          ),
          actions: [
            if (showDetails && next.error.diagnostics?.isEmpty == false)
              TextButton(
                onPressed: () {
                  final sheetContext =
                      navigatorKey?.currentContext ??
                      scaffoldMessengerKey?.currentContext ??
                      context;
                  showErrorDetailsSheet(sheetContext, next.error);
                },
                child: const Text('查看详情'),
              ),
            TextButton(
              onPressed: () {
                ref.read(apiErrorReporterProvider.notifier).clear();
              },
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });

    return child;
  }
}
