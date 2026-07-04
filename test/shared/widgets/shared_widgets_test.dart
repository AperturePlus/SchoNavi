import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/error/api_error_reporter.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/error/error_diagnostics.dart';
import 'package:scho_navi/core/theme/app_colors.dart';
import 'package:scho_navi/core/theme/app_theme.dart';
import 'package:scho_navi/domain/entities/match_level.dart';
import 'package:scho_navi/domain/entities/recommendation.dart';
import 'package:scho_navi/shared/widgets/api_error_banner_listener.dart';
import 'package:scho_navi/shared/widgets/api_error_notice.dart';
import 'package:scho_navi/shared/widgets/bento_tile.dart';
import 'package:scho_navi/shared/widgets/empty_view.dart';
import 'package:scho_navi/shared/widgets/error_view.dart';
import 'package:scho_navi/shared/widgets/loading_view.dart';
import 'package:scho_navi/shared/widgets/match_level_chip.dart';
import 'package:scho_navi/shared/widgets/professor_card.dart';

Widget _wrap(
  Widget child, {
  ThemeData? theme,
  bool showApiErrorDetails = false,
}) => ProviderScope(
  overrides: [
    initialAppConfigProvider.overrideWithValue(
      AppConfig(
        featureFlags: FeatureFlags(showApiErrorDetails: showApiErrorDetails),
      ),
    ),
  ],
  child: MaterialApp(
    theme: theme,
    home: Scaffold(body: child),
  ),
);

Widget _wrapBanner({required bool showApiErrorDetails}) {
  const error = ServerException(
    diagnostics: ErrorDiagnostics(
      requestId: 'banner-request-id',
      method: 'GET',
      path: '/api/v1/history',
      httpStatus: 500,
      context: {'操作': 'listSessions', '会话 ID': 'session-1'},
    ),
  );
  return _wrap(
    ApiErrorBannerListener(
      child: Builder(
        builder: (context) => Column(
          children: [
            TextButton(
              onPressed: () {
                ProviderScope.containerOf(context)
                    .read(apiErrorReporterProvider.notifier)
                    .report('历史刷新失败', error);
              },
              child: const Text('report-first'),
            ),
            TextButton(
              onPressed: () {
                ProviderScope.containerOf(context)
                    .read(apiErrorReporterProvider.notifier)
                    .report(
                      '收藏刷新失败',
                      const ValidationException(
                        '收藏同步失败',
                        diagnostics: ErrorDiagnostics(
                          requestId: 'latest-request-id',
                          method: 'GET',
                          path: '/api/v1/favorites',
                        ),
                      ),
                    );
              },
              child: const Text('report-second'),
            ),
          ],
        ),
      ),
    ),
    showApiErrorDetails: showApiErrorDetails,
  );
}

Widget _wrapBannerWithAppKeys({required bool showApiErrorDetails}) {
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  const error = ServerException(
    message: '服务返回格式异常',
    diagnostics: ErrorDiagnostics(
      requestId: 'profile-request-id',
      method: 'GET',
      path: '/api/v1/profile',
      httpStatus: 500,
    ),
  );
  return ProviderScope(
    overrides: [
      initialAppConfigProvider.overrideWithValue(
        AppConfig(
          featureFlags: FeatureFlags(showApiErrorDetails: showApiErrorDetails),
        ),
      ),
    ],
    child: ApiErrorBannerListener(
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorKey: navigatorKey,
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                ProviderScope.containerOf(context)
                    .read(apiErrorReporterProvider.notifier)
                    .report('个人资料同步失败', error);
              },
              child: const Text('report-keyed'),
            ),
          ),
        ),
      ),
    ),
  );
}

void _expectProfessorCardOutline(WidgetTester tester) {
  final cardFinder = find.byType(ProfessorCard);
  final tile = tester.widget<BentoTile>(
    find.descendant(of: cardFinder, matching: find.byType(BentoTile)),
  );
  final border = tile.border! as Border;
  final outline = Theme.of(tester.element(cardFinder)).colorScheme.outline;

  expect(tile.borderRadius, 18);
  for (final side in [border.top, border.right, border.bottom, border.left]) {
    expect(side.color, outline);
    expect(side.width, 1);
  }
  expect(
    find.descendant(
      of: cardFinder,
      matching: find.byWidgetPredicate(
        (widget) => widget is Container && widget.color == AppColors.indigo,
      ),
    ),
    findsNothing,
  );
}

void main() {
  testWidgets('LoadingView shows a progress indicator', (tester) async {
    await tester.pumpWidget(_wrap(const LoadingView()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ErrorView shows message and retry calls back', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(ErrorView(message: '服务异常', onRetry: () => tapped = true)),
    );
    expect(find.text('服务异常'), findsOneWidget);
    await tester.tap(find.text('重试'));
    expect(tapped, isTrue);
  });

  testWidgets('ErrorView exposes request ID and gates integration details', (
    tester,
  ) async {
    final error = ServerException(
      diagnostics: ErrorDiagnostics(
        requestId: 'request-123',
        method: 'GET',
        path: '/api/v1/profile',
        httpStatus: 500,
      ),
    );
    await tester.pumpWidget(_wrap(ErrorView(error: error)));
    expect(find.textContaining('request-123'), findsOneWidget);
    expect(find.text('联调详情'), findsNothing);

    await tester.pumpWidget(
      _wrap(ErrorView(error: error), showApiErrorDetails: true),
    );
    await tester.tap(find.text('联调详情'));
    await tester.pumpAndSettle();
    expect(find.text('联调错误详情'), findsOneWidget);
    expect(find.text('/api/v1/profile'), findsOneWidget);
    expect(find.text('复制全部详情'), findsOneWidget);
  });

  testWidgets('ApiErrorBannerListener shows latest error and closes', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapBanner(showApiErrorDetails: false));

    await tester.tap(find.text('report-first'));
    await tester.pumpAndSettle();
    expect(find.textContaining('历史刷新失败'), findsOneWidget);
    expect(find.textContaining('banner-request-id'), findsOneWidget);
    expect(find.text('查看详情'), findsNothing);

    await tester.tap(find.text('report-second'));
    await tester.pumpAndSettle();
    expect(find.textContaining('历史刷新失败'), findsNothing);
    expect(find.textContaining('收藏刷新失败'), findsOneWidget);
    expect(find.textContaining('latest-request-id'), findsOneWidget);

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.textContaining('收藏刷新失败'), findsNothing);
  });

  testWidgets('ApiErrorBannerListener gates details and copies diagnostics', (
    tester,
  ) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.setData') {
            final data = methodCall.arguments as Map<dynamic, dynamic>;
            clipboardText = data['text'] as String?;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(_wrapBanner(showApiErrorDetails: true));

    await tester.tap(find.text('report-first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text('联调错误详情'), findsOneWidget);
    expect(find.text('/api/v1/history'), findsOneWidget);
    await tester.tap(find.text('复制全部详情'));
    await tester.pump();

    expect(clipboardText, contains('banner-request-id'));
    expect(clipboardText, contains('/api/v1/history'));
    expect(clipboardText, contains('[基础信息]'));
    expect(clipboardText, contains('[上下文]'));
    expect(clipboardText, contains('操作: listSessions'));
    expect(clipboardText, contains('会话 ID: session-1'));
  });

  testWidgets('ApiErrorBannerListener opens details with app keys', (
    tester,
  ) async {
    await tester.pumpWidget(_wrapBannerWithAppKeys(showApiErrorDetails: true));

    await tester.tap(find.text('report-keyed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('个人资料同步失败'), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    expect(find.text('联调错误详情'), findsOneWidget);
    expect(find.text('/api/v1/profile'), findsOneWidget);
  });

  testWidgets('ApiErrorNotice shows request ID, details and actions', (
    tester,
  ) async {
    var retried = false;
    var abandoned = false;
    const error = ValidationException(
      '输入内容不合法',
      diagnostics: ErrorDiagnostics(
        requestId: 'notice-request-id',
        method: 'POST',
        path: '/api/v1/chat/sessions/s1/turns',
        backendCode: 'VALIDATION_ERROR',
      ),
    );

    await tester.pumpWidget(
      _wrap(
        ApiErrorNotice(
          message: error.message,
          error: error,
          primaryLabel: '重试本轮',
          onPrimary: () => retried = true,
          secondaryLabel: '放弃本轮',
          onSecondary: () => abandoned = true,
        ),
        showApiErrorDetails: true,
      ),
    );

    expect(find.text('输入内容不合法'), findsOneWidget);
    expect(find.textContaining('notice-request-id'), findsOneWidget);
    expect(find.text('联调详情'), findsOneWidget);
    expect(find.text('重试本轮'), findsOneWidget);
    expect(find.text('放弃本轮'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ApiErrorNotice)).flagsCollection.isLiveRegion,
      isTrue,
    );

    await tester.tap(find.text('重试本轮'));
    await tester.tap(find.text('放弃本轮'));
    expect(retried, isTrue);
    expect(abandoned, isTrue);

    await tester.tap(find.text('联调详情'));
    await tester.pumpAndSettle();
    expect(find.text('/api/v1/chat/sessions/s1/turns'), findsOneWidget);
  });

  testWidgets('EmptyView shows hint and edit action', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      _wrap(
        EmptyView(
          message: '暂未找到完全符合条件的导师',
          actionLabel: '修改条件',
          onAction: () => edited = true,
        ),
      ),
    );
    expect(find.textContaining('暂未找到'), findsOneWidget);
    await tester.tap(find.text('修改条件'));
    expect(edited, isTrue);
  });

  testWidgets('MatchLevelChip renders the level label', (tester) async {
    await tester.pumpWidget(
      _wrap(const MatchLevelChip(level: MatchLevel.high)),
    );
    expect(find.textContaining('高'), findsOneWidget);
  });

  testWidgets('ProfessorCard shows name/university and triggers onTap', (
    tester,
  ) async {
    var tapped = false;
    const rec = Recommendation(
      professorId: 'p_001',
      name: '张三',
      university: '上海交通大学',
      college: '电子信息与电气工程学院',
      title: '教授',
      researchFields: ['医学影像', '计算机视觉'],
      matchLevel: MatchLevel.high,
      reason: '方向相关。',
      limitations: [],
    );
    await tester.pumpWidget(
      _wrap(ProfessorCard(recommendation: rec, onTap: () => tapped = true)),
    );
    expect(find.text('张三'), findsOneWidget);
    expect(find.textContaining('上海交通大学'), findsOneWidget);
    await tester.tap(find.byType(ProfessorCard));
    expect(tapped, isTrue);
  });

  testWidgets(
    'ProfessorCard uses themed rounded outline without accent strip',
    (tester) async {
      const rec = Recommendation(
        professorId: 'p_001',
        name: '张三',
        university: '上海交通大学',
        college: '电子信息与电气工程学院',
        title: '教授',
        researchFields: ['医学影像', '计算机视觉'],
        matchLevel: MatchLevel.high,
        reason: '方向相关。',
        limitations: [],
      );

      for (final theme in [AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(
          _wrap(
            ProfessorCard(recommendation: rec, onTap: () {}),
            theme: theme,
          ),
        );
        _expectProfessorCardOutline(tester);
      }
    },
  );
}
