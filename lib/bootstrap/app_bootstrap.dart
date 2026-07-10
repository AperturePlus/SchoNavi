import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../core/config/app_config.dart';
import '../core/di/providers.dart';
import '../core/theme/app_theme.dart';
import '../features/splash/pages/splash_page.dart';
import '../shared/widgets/cool_scaffold_background.dart';

typedef PreferencesLoader = Future<SharedPreferences> Function();

/// Coordinates the Flutter splash animation with the minimum local bootstrap.
///
/// [runApp] is called before preferences are loaded, so the native launch
/// screen can hand off to Flutter immediately. The real application is mounted
/// only after both preferences and the splash animation are complete.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.initialAppConfig = const AppConfig(),
    this.preferencesLoader,
    this.dioOverride,
    this.identityDioOverride,
  });

  final AppConfig initialAppConfig;

  /// Injectable for startup tests and retry handling.
  final PreferencesLoader? preferencesLoader;

  /// 测试注入：覆盖 [dioProvider] 的 Dio 实例，避免全 App widget 测试发起
  /// 真实网络调用。生产路径为 null（走 [dioProvider] 默认构造）。
  final Dio? dioOverride;

  /// 测试注入：覆盖 [apiIdentityDioProvider]。生产路径为 null。
  final Dio? identityDioOverride;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SharedPreferences? _preferences;
  Object? _loadError;
  bool _splashFinished = false;
  bool _loading = false;
  int _loadAttempt = 0;
  int _splashGeneration = 0;

  PreferencesLoader get _loader =>
      widget.preferencesLoader ?? SharedPreferences.getInstance;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final attempt = ++_loadAttempt;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final preferences = await _loader();
      if (!mounted || attempt != _loadAttempt) return;
      setState(() {
        _preferences = preferences;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || attempt != _loadAttempt) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _finishSplash() {
    if (_splashFinished || _preferences == null) return;
    setState(() => _splashFinished = true);
  }

  void _retry() {
    setState(() => _splashGeneration++);
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (_splashFinished && preferences != null) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          initialAppConfigProvider.overrideWithValue(widget.initialAppConfig),
          if (widget.dioOverride != null)
            dioProvider.overrideWithValue(widget.dioOverride!),
          if (widget.identityDioOverride != null)
            apiIdentityDioProvider.overrideWithValue(
              widget.identityDioOverride!,
            ),
        ],
        child: const SchoNaviApp(),
      );
    }

    return ProviderScope(
      key: ValueKey(_splashGeneration),
      child: MaterialApp(
        title: 'SchoNavi',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: _loadError == null
            ? SplashPage(
                readyToExit: preferences != null,
                onFinished: _finishSplash,
              )
            : _StartupErrorView(loading: _loading, onRetry: _retry),
      ),
    );
  }
}

class _StartupErrorView extends StatelessWidget {
  const _StartupErrorView({required this.loading, required this.onRetry});

  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CoolScaffoldBackground.wrap(
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Semantics(
                liveRegion: true,
                label: '启动失败，请重试',
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sync_problem_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text('启动失败', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '无法读取本地数据，请重试。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: loading ? null : onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(loading ? '正在重试' : '重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
