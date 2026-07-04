import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/di/providers.dart';
import 'core/platform/preparation_reminder_platform.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/preparation/providers/preparation_reminder_providers.dart';
import 'shared/widgets/api_error_banner_listener.dart';

class SchoNaviApp extends ConsumerStatefulWidget {
  const SchoNaviApp({super.key});

  @override
  ConsumerState<SchoNaviApp> createState() => _SchoNaviAppState();
}

class _SchoNaviAppState extends ConsumerState<SchoNaviApp> {
  var _initialRouteHandled = false;
  PreparationReminderPlatform? _reminderPlatform;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void dispose() {
    _reminderPlatform?.setRouteHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    ref.watch(preparationReminderSyncProvider);
    _bindPreparationReminderRoutes(router);
    return ApiErrorBannerListener(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorKey: rootNavigatorKey,
      child: MaterialApp.router(
        title: 'SchoNavi',
        scaffoldMessengerKey: _scaffoldMessengerKey,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: router,
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          physics: const BouncingScrollPhysics(),
        ),
      ),
    );
  }

  void _bindPreparationReminderRoutes(GoRouter router) {
    final platform = ref.read(preparationReminderPlatformProvider);
    _reminderPlatform = platform;
    platform.setRouteHandler(router.go);
    if (_initialRouteHandled) return;
    _initialRouteHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final route = await platform.takeInitialRoute();
      if (!mounted || route == null) return;
      router.go(route);
    });
  }
}
