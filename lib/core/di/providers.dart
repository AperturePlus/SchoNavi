import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/http/api_auth.dart';
import '../../data/http/api_request_id_interceptor.dart';
import '../../data/http/http_chat_repository.dart';
import '../../data/http/http_comparison_repository.dart';
import '../../data/http/http_competition_catalog_repository.dart';
import '../../data/http/http_competition_recommendation_repository.dart';
import '../../data/http/http_conversation_repository.dart';
import '../../data/http/http_favorite_repository.dart';
import '../../data/http/http_feedback_repository.dart';
import '../../data/http/http_history_repository.dart';
import '../../data/http/http_home_config_repository.dart';
import '../../data/http/http_home_prompt_repository.dart';
import '../../data/http/http_match_analysis_repository.dart';
import '../../data/http/http_outreach_email_repository.dart';
import '../../data/http/http_professor_repository.dart';
import '../../data/http/http_profile_extraction_repository.dart';
import '../../data/http/http_profile_repository.dart';
import '../../data/http/http_quick_actions_source.dart';
import '../../data/http/http_recommendation_need_classifier.dart';
import '../../data/http/http_recommendation_repository.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/favorite_item.dart';
import '../../domain/entities/home_config.dart';
import '../../domain/entities/home_prompt.dart';
import '../../domain/entities/recommended_competition.dart';
import '../../domain/entities/search_history_item.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/comparison_repository.dart';
import '../../domain/repositories/competition_catalog_repository.dart';
import '../../domain/repositories/competition_recommendation_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/favorite_repository.dart';
import '../../domain/repositories/feedback_repository.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/home_config_repository.dart';
import '../../domain/repositories/home_prompt_repository.dart';
import '../../domain/repositories/match_analysis_repository.dart';
import '../../domain/repositories/outreach_email_repository.dart';
import '../../domain/repositories/professor_repository.dart';
import '../../domain/repositories/profile_extraction_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../../shared/utils/quick_actions_source.dart';
import '../../shared/utils/recommendation_need_classifier.dart';
import '../auth/anonymous_credential_store.dart';
import '../config/app_config.dart';
import '../error/api_error_reporter.dart';
import '../launcher/link_launcher.dart';
import '../launcher/url_launcher_link_launcher.dart';
import '../result/result.dart';
import '../storage/local_store.dart';
import '../storage/shared_preferences_local_store.dart';

BaseOptions _apiBaseOptions(AppConfig cfg) {
  return BaseOptions(
    baseUrl: cfg.api.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 120),
    sendTimeout: const Duration(seconds: 30),
    headers: const {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    },
  );
}

final apiIdentityDioProvider = Provider<Dio>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return Dio(_apiBaseOptions(cfg))..interceptors.add(ApiRequestIdInterceptor());
});

final anonymousCredentialStoreProvider = Provider<AnonymousCredentialStore>(
  (ref) => const SecureAnonymousCredentialStore(FlutterSecureStorage()),
);

final apiAuthenticatorProvider = Provider<ApiAuthenticator>((ref) {
  return ApiAuthenticator(
    ref.watch(apiIdentityDioProvider),
    ref.watch(anonymousCredentialStoreProvider),
  );
});

/// Authenticated Dio for the first-party API.
final dioProvider = Provider<Dio>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return Dio(_apiBaseOptions(cfg))
    ..interceptors.add(ApiRequestIdInterceptor())
    ..interceptors.add(ApiAuthInterceptor(ref.watch(apiAuthenticatorProvider)));
});

final apiDioProvider = Provider<Dio>((ref) => ref.watch(dioProvider));

final recommendationNeedClassifierProvider =
    Provider<RecommendationNeedClassifier>(
      (ref) => HttpRecommendationNeedClassifier(ref.watch(apiDioProvider)),
    );

final quickActionsSourceProvider = Provider<QuickActionsSource>(
  (ref) => HttpQuickActionsSource(ref.watch(apiDioProvider)),
);

final recommendationRepositoryProvider = Provider<RecommendationRepository>(
  (ref) => HttpRecommendationRepository(ref.watch(apiDioProvider)),
);

final competitionRecommendationRepositoryProvider =
    Provider<CompetitionRecommendationRepository>(
      (ref) =>
          HttpCompetitionRecommendationRepository(ref.watch(apiDioProvider)),
    );

final competitionCatalogRepositoryProvider =
    Provider<CompetitionCatalogRepository>(
      (ref) => HttpCompetitionCatalogRepository(ref.watch(apiDioProvider)),
    );

final competitionByIdProvider =
    FutureProvider.family<RecommendedCompetition?, String>((ref, id) {
      return ref.watch(competitionCatalogRepositoryProvider).fetchById(id);
    });

final professorRepositoryProvider = Provider<ProfessorRepository>(
  (ref) => HttpProfessorRepository(ref.watch(apiDioProvider)),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => HttpChatRepository(ref.watch(apiDioProvider)),
);

final conversationRepositoryProvider = Provider<ConversationRepository>(
  (ref) => HttpConversationRepository(ref.watch(apiDioProvider)),
);

final conversationHistoryProvider = FutureProvider<List<ConversationSession>>((
  ref,
) async {
  final result = await ref.watch(conversationRepositoryProvider).listSessions();
  return switch (result) {
    Success<List<ConversationSession>>(:final data) => data,
    Failure<List<ConversationSession>>(:final error) => throw error,
  };
});

final comparisonRepositoryProvider = Provider<ComparisonRepository>(
  (ref) => HttpComparisonRepository(ref.watch(apiDioProvider)),
);

final matchAnalysisRepositoryProvider = Provider<MatchAnalysisRepository>(
  (ref) => HttpMatchAnalysisRepository(ref.watch(apiDioProvider)),
);

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => HttpProfileRepository(ref.watch(apiDioProvider)),
);

final outreachEmailRepositoryProvider = Provider<OutreachEmailRepository>(
  (ref) => HttpOutreachEmailRepository(ref.watch(apiDioProvider)),
);

final profileExtractionRepositoryProvider =
    Provider<ProfileExtractionRepository>(
      (ref) => HttpProfileExtractionRepository(ref.watch(apiDioProvider)),
    );

final homePromptRepositoryProvider = Provider<HomePromptRepository>(
  (ref) => HttpHomePromptRepository(ref.watch(apiDioProvider)),
);

final homeConfigRepositoryProvider = Provider<HomeConfigRepository>(
  (ref) => HttpHomeConfigRepository(ref.watch(apiDioProvider)),
);

final homeConfigProvider = FutureProvider.family<HomeConfig, String>((
  ref,
  mode,
) {
  return ref.watch(homeConfigRepositoryProvider).fetchConfig(mode);
});

final homePromptsProvider = FutureProvider.family<List<HomePrompt>, String>((
  ref,
  mode,
) {
  return ref
      .watch(homeConfigProvider(mode).future)
      .then((config) => config.prompts);
});

/// 在 main() 中用 SharedPreferences.getInstance() 的结果 override。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with '
    'SharedPreferences.getInstance()',
  ),
);

/// 仅保存主题、匿名状态和备赛相关的必要本地状态。
final localStoreProvider = Provider<LocalStore>(
  (ref) => SharedPreferencesLocalStore(ref.watch(sharedPreferencesProvider)),
);

const appThemeModePreferenceKey = 'themeMode';

final appThemeModeProvider =
    NotifierProvider<AppThemeModeController, ThemeMode>(
      AppThemeModeController.new,
    );

class AppThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = ref
        .watch(localStoreProvider)
        .getString(appThemeModePreferenceKey);
    return _decode(raw);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(localStoreProvider)
        .setString(appThemeModePreferenceKey, _encode(mode));
  }

  static ThemeMode _decode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.system,
  };

  static String _encode(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const UrlLauncherLinkLauncher(),
);

final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  final repo = HttpFavoriteRepository(
    ref.watch(apiDioProvider),
    onSyncError: (error) =>
        ref.read(apiErrorReporterProvider.notifier).report('收藏同步失败', error),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final favoritesProvider = StreamProvider<List<FavoriteItem>>((ref) {
  return ref.watch(favoriteRepositoryProvider).watch();
});

final favoriteStatusProvider = StreamProvider.family<bool, String>((
  ref,
  professorId,
) {
  return ref
      .watch(favoriteRepositoryProvider)
      .watch()
      .map((items) => items.any((item) => item.professorId == professorId));
});

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  final repo = HttpHistoryRepository(
    ref.watch(apiDioProvider),
    onSyncError: (error) =>
        ref.read(apiErrorReporterProvider.notifier).report('历史同步失败', error),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final searchHistoryProvider = StreamProvider<List<SearchHistoryItem>>((ref) {
  return ref.watch(historyRepositoryProvider).watch();
});

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => HttpFeedbackRepository(ref.watch(apiDioProvider)),
);
