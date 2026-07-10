import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/di/providers.dart';
import '../../../core/error/api_error_reporter.dart';
import '../../../domain/entities/user_profile.dart';

/// 全局当前学生档案。向导/中心通过它编辑，推荐/套磁/匹配读它。
class ProfileController extends Notifier<UserProfile> {
  Future<UserProfile?>? _remoteRefreshInFlight;

  @override
  UserProfile build() {
    final repo = ref.watch(profileRepositoryProvider);
    if (ref.watch(appConfigProvider).api.isConfigured) {
      Future<void>.microtask(() async {
        await ensureLoadedForProfileGate();
      });
    }
    return repo.load();
  }

  Future<UserProfile?> ensureLoadedForProfileGate() {
    if (!state.isEmpty) return Future.value(state);

    if (!ref.read(appConfigProvider).api.isConfigured)
      return Future.value(state);
    return _refreshRemoteProfileSafely();
  }

  Future<void> refresh() async {
    state = await ref.read(profileRepositoryProvider).refresh();
  }

  Future<void> save(UserProfile profile) async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.save(profile);
    state = repo.load();
  }

  Future<UserProfile?> _refreshRemoteProfileSafely() {
    final inFlight = _remoteRefreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _refreshRemoteProfile();
    _remoteRefreshInFlight = refresh;
    refresh.whenComplete(() {
      if (identical(_remoteRefreshInFlight, refresh)) {
        _remoteRefreshInFlight = null;
      }
    });
    return refresh;
  }

  Future<UserProfile?> _refreshRemoteProfile() async {
    try {
      final refreshed = await ref.read(profileRepositoryProvider).refresh();
      if (ref.mounted) state = refreshed;
      return refreshed;
    } catch (error, stackTrace) {
      if (ref.mounted) {
        ref
            .read(apiErrorReporterProvider.notifier)
            .report('个人资料同步失败', error, stackTrace);
      }
      return null;
    }
  }
}

final profileProvider = NotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);
