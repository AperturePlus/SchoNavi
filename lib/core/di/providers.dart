import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/ai/ai_chat_repository.dart';
import '../../data/ai/ai_comparison_repository.dart';
import '../../data/ai/ai_competition_recommendation_repository.dart';
import '../../data/ai/ai_match_analysis_repository.dart';
import '../../data/ai/ai_outreach_email_repository.dart';
import '../../data/ai/ai_profile_extraction_repository.dart';
import '../../data/ai/ai_recommendation_repository.dart';
import '../../data/ai/llm_recommendation_intent_classifier.dart';
import '../../data/ai/llm_recommendation_need_classifier.dart';
import '../../data/ai/llm_quick_actions_source.dart';
import '../../data/ai/professor_candidate_source.dart';
import '../../data/fixtures/competition_catalog.dart';
import '../../data/fixtures/competition_catalog_repository_impl.dart';
import '../../data/http/api_auth.dart';
import '../../data/http/api_request_id_interceptor.dart';
import '../../data/http/http_chat_repository.dart';
import '../../data/http/http_conversation_repository.dart';
import '../../data/http/http_competition_catalog_repository.dart';
import '../../data/http/http_comparison_repository.dart';
import '../../data/http/http_competition_recommendation_repository.dart';
import '../../data/http/http_favorite_repository.dart';
import '../../data/http/http_feedback_repository.dart';
import '../../data/http/http_history_repository.dart';
import '../../data/http/http_home_config_repository.dart';
import '../../data/local/local_chat_history_store.dart';
import '../../data/local/local_conversation_repository.dart';
import '../../data/local/local_favorite_repository.dart';
import '../../data/local/local_history_repository.dart';
import '../../data/local/local_profile_repository.dart';
import '../../data/local/memory_conversation_store.dart';
import '../../data/mock/mock_db.dart';
import '../../data/mock/mock_professor_repository.dart';
import '../../data/http/http_home_prompt_repository.dart';
import '../../data/http/http_match_analysis_repository.dart';
import '../../data/http/http_outreach_email_repository.dart';
import '../../data/http/http_professor_repository.dart';
import '../../data/http/http_profile_extraction_repository.dart';
import '../../data/http/http_profile_repository.dart';
import '../../data/http/http_quick_actions_source.dart';
import '../../data/http/http_recommendation_need_classifier.dart';
import '../../data/http/http_recommendation_repository.dart';
import '../../data/mock/mock_home_config_repository.dart';
import '../../data/mock/mock_home_prompt_repository.dart';
import '../../data/mock/mock_feedback_repository.dart';
import '../../domain/entities/conversation_session.dart';
import '../../domain/entities/favorite_item.dart';
import '../../domain/entities/home_config.dart';
import '../../domain/entities/home_prompt.dart';
import '../../domain/entities/recommended_competition.dart';
import '../../domain/entities/search_history_item.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/comparison_repository.dart';
import '../../domain/repositories/competition_catalog_repository.dart';
import '../../domain/repositories/competition_recommendation_repository.dart';
import '../../domain/repositories/favorite_repository.dart';
import '../../domain/repositories/feedback_repository.dart';
import '../../domain/repositories/history_repository.dart';
import '../../domain/repositories/home_config_repository.dart';
import '../../domain/repositories/home_prompt_repository.dart';
import '../../domain/repositories/match_analysis_repository.dart';
import '../../domain/repositories/outreach_email_repository.dart';
import '../../domain/repositories/professor_repository.dart';
import '../../domain/repositories/profile_repository.dart';
import '../../domain/repositories/profile_extraction_repository.dart';
import '../../domain/repositories/recommendation_repository.dart';
import '../../shared/utils/recommendation_intent_router.dart';
import '../../shared/utils/recommendation_need_classifier.dart';
import '../../shared/utils/quick_actions_source.dart';
import '../ai/deepseek_llm_client.dart';
import '../auth/anonymous_credential_store.dart';
import '../ai/llm_client.dart';
import '../ai/llm_trace.dart';
import '../ai/missing_llm_client.dart';
import '../config/app_config.dart';
import '../error/api_error_reporter.dart';
import '../launcher/link_launcher.dart';
import '../launcher/url_launcher_link_launcher.dart';
import '../result/result.dart';
import '../storage/local_store.dart';
import '../storage/shared_preferences_local_store.dart';

final mockDbProvider = Provider<MockDb>((ref) => MockDb());

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

/// Authenticated Dio for the first-party API. Tests may still override
/// [dioProvider]; [apiDioProvider] intentionally follows it for compatibility.
final dioProvider = Provider<Dio>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return Dio(_apiBaseOptions(cfg))
    ..interceptors.add(ApiRequestIdInterceptor())
    ..interceptors.add(ApiAuthInterceptor(ref.watch(apiAuthenticatorProvider)));
});

final apiDioProvider = Provider<Dio>((ref) => ref.watch(dioProvider));

final llmDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );
});

final llmClientProvider = Provider<LlmClient>((ref) {
  final cfg = ref.watch(appConfigProvider);
  if (!cfg.llm.isConfigured) return const MissingLlmClient();
  final base = DeepSeekLlmClient(
    dio: ref.watch(llmDioProvider),
    apiKey: cfg.llm.apiKey,
    baseUrl: cfg.llm.baseUrl,
    model: cfg.llm.model,
  );
  if (!cfg.featureFlags.showAiTrace) return base;
  return TracingLlmClient(
    delegate: base,
    model: cfg.llm.model,
    onTrace: (trace) => ref.read(aiTraceProvider.notifier).record(trace),
  );
});

final professorCandidateSourceProvider = Provider<ProfessorCandidateSource>(
  (ref) => MockDbCandidateSource(ref.watch(mockDbProvider)),
);

final competitionCandidateSourceProvider = Provider<CompetitionCandidateSource>(
  (ref) {
    return const StaticCompetitionCandidateSource();
  },
);

final recommendationIntentClassifierProvider =
    Provider<RecommendationIntentClassifier>((ref) {
      return LlmRecommendationIntentClassifier(ref.watch(llmClientProvider));
    });

/// 对话式推荐：用 LLM 判定追问是否需要新一轮推荐（产卡）。
/// 失败降级为 false（不阻断对话）。见 spec §4.5。
final recommendationNeedClassifierProvider =
    Provider<RecommendationNeedClassifier>((ref) {
      return switch (ref.watch(appConfigProvider).dataSource) {
        DataSource.llm => LlmRecommendationNeedClassifier(
          ref.watch(llmClientProvider),
        ),
        DataSource.http => HttpRecommendationNeedClassifier(
          ref.watch(apiDioProvider),
        ),
      };
    });

/// 快捷操作 chip 的后端来源。失败返回 [Failure]（由 ChatNotifier 填硬编码
/// 兜底常量），成功空返回 [Success] 空列表（不显示 chip）。见 spec §5。
final quickActionsSourceProvider = Provider<QuickActionsSource>((ref) {
  return switch (ref.watch(appConfigProvider).dataSource) {
    DataSource.llm => LlmQuickActionsSource(ref.watch(llmClientProvider)),
    DataSource.http => HttpQuickActionsSource(ref.watch(apiDioProvider)),
  };
});

final recommendationRepositoryProvider = Provider<RecommendationRepository>((
  ref,
) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return AiRecommendationRepository(
        llm: ref.watch(llmClientProvider),
        candidates: ref.watch(professorCandidateSourceProvider),
      );
    case DataSource.http:
      return HttpRecommendationRepository(ref.watch(apiDioProvider));
  }
});

final competitionRecommendationRepositoryProvider =
    Provider<CompetitionRecommendationRepository>((ref) {
      switch (ref.watch(appConfigProvider).dataSource) {
        case DataSource.llm:
          return AiCompetitionRecommendationRepository(
            llm: ref.watch(llmClientProvider),
            candidates: ref.watch(competitionCandidateSourceProvider),
          );
        case DataSource.http:
          return HttpCompetitionRecommendationRepository(
            ref.watch(apiDioProvider),
          );
      }
    });

final competitionCatalogRepositoryProvider =
    Provider<CompetitionCatalogRepository>((ref) {
      return switch (ref.watch(appConfigProvider).dataSource) {
        DataSource.llm => const StaticCompetitionCatalogRepository(),
        DataSource.http => HttpCompetitionCatalogRepository(
          ref.watch(apiDioProvider),
        ),
      };
    });

final competitionByIdProvider =
    FutureProvider.family<RecommendedCompetition?, String>((ref, id) {
      return ref.watch(competitionCatalogRepositoryProvider).fetchById(id);
    });

final professorRepositoryProvider = Provider<ProfessorRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return MockProfessorRepository(ref.watch(mockDbProvider));
    case DataSource.http:
      return HttpProfessorRepository(ref.watch(apiDioProvider));
  }
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return AiChatRepository(
        llm: ref.watch(llmClientProvider),
        db: ref.watch(mockDbProvider),
        historyStore: LocalChatHistoryStore(ref.watch(localStoreProvider)),
      );
    case DataSource.http:
      return HttpChatRepository(ref.watch(apiDioProvider));
  }
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return LocalConversationRepository(
        store: MemoryConversationStore(),
        llm: ref.watch(llmClientProvider),
        recommendations: ref.watch(recommendationRepositoryProvider),
        classifier: ref.watch(recommendationNeedClassifierProvider),
        quickActions: ref.watch(quickActionsSourceProvider),
        db: ref.watch(mockDbProvider),
        profile: () => ref.read(profileRepositoryProvider).load(),
      );
    case DataSource.http:
      return HttpConversationRepository(ref.watch(apiDioProvider));
  }
});

final conversationHistoryProvider = FutureProvider<List<ConversationSession>>((
  ref,
) async {
  final result = await ref.watch(conversationRepositoryProvider).listSessions();
  return switch (result) {
    Success<List<ConversationSession>>(:final data) => data,
    Failure<List<ConversationSession>>(:final error) => throw error,
  };
});

final comparisonRepositoryProvider = Provider<ComparisonRepository>((ref) {
  final professorRepo = ref.watch(professorRepositoryProvider);
  switch (ref.watch(appConfigProvider).dataSource) {
    case DataSource.llm:
      return AiComparisonRepository(
        llm: ref.watch(llmClientProvider),
        professorRepository: professorRepo,
      );
    case DataSource.http:
      return HttpComparisonRepository(ref.watch(apiDioProvider));
  }
});

final matchAnalysisRepositoryProvider = Provider<MatchAnalysisRepository>((
  ref,
) {
  switch (ref.watch(appConfigProvider).dataSource) {
    case DataSource.llm:
      return AiMatchAnalysisRepository(ref.watch(llmClientProvider));
    case DataSource.http:
      return HttpMatchAnalysisRepository(ref.watch(apiDioProvider));
  }
});
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return LocalProfileRepository(ref.watch(localStoreProvider));
    case DataSource.http:
      return HttpProfileRepository(ref.watch(apiDioProvider));
  }
});

final outreachEmailRepositoryProvider = Provider<OutreachEmailRepository>((
  ref,
) {
  final cfg = ref.watch(appConfigProvider);
  switch (cfg.dataSource) {
    case DataSource.llm:
      return AiOutreachEmailRepository(ref.watch(llmClientProvider));
    case DataSource.http:
      return HttpOutreachEmailRepository(ref.watch(apiDioProvider));
  }
});

/// 成果抽取：LLM 模式调用大模型，http 模式走真实后端抽取接口。
final profileExtractionRepositoryProvider =
    Provider<ProfileExtractionRepository>((ref) {
      final cfg = ref.watch(appConfigProvider);
      return switch (cfg.dataSource) {
        DataSource.llm => AiProfileExtractionRepository(
          ref.watch(llmClientProvider),
        ),
        DataSource.http => HttpProfileExtractionRepository(
          ref.watch(apiDioProvider),
        ),
      };
    });

/// 首页快捷 prompt 仓库。llm 模式使用本地 mock，http 模式走真实后端。
final homePromptRepositoryProvider = Provider<HomePromptRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return switch (cfg.dataSource) {
    DataSource.llm => const MockHomePromptRepository(),
    DataSource.http => HttpHomePromptRepository(ref.watch(apiDioProvider)),
  };
});

final homeConfigRepositoryProvider = Provider<HomeConfigRepository>((ref) {
  return switch (ref.watch(appConfigProvider).dataSource) {
    DataSource.llm => const MockHomeConfigRepository(),
    DataSource.http => HttpHomeConfigRepository(ref.watch(apiDioProvider)),
  };
});

final homeConfigProvider = FutureProvider.family<HomeConfig, String>((
  ref,
  mode,
) {
  return ref.watch(homeConfigRepositoryProvider).fetchConfig(mode);
});

/// 首页快捷 prompt 列表，按模式（mentor / competition）缓存。
final homePromptsProvider = FutureProvider.family<List<HomePrompt>, String>((
  ref,
  mode,
) {
  return ref
      .watch(homeConfigProvider(mode).future)
      .then((config) => config.prompts);
});

/// 在 main() 中用 SharedPreferences.getInstance() 的结果 override。
/// 未 override 直接读取会抛错，提醒接线缺失。
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main() with '
    'SharedPreferences.getInstance()',
  ),
);

/// 全应用本地持久化入口。收藏/历史/登录态/首启标记均经此存取。
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

/// 外链打开（教师主页等）。feature 层只依赖 [LinkLauncher] 接口，便于注入假实现。
final linkLauncherProvider = Provider<LinkLauncher>(
  (ref) => const UrlLauncherLinkLauncher(),
);

final favoriteRepositoryProvider = Provider<FavoriteRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  final FavoriteRepository repo;
  switch (cfg.dataSource) {
    case DataSource.llm:
    case DataSource.http:
      repo = cfg.dataSource == DataSource.http
          ? HttpFavoriteRepository(
              ref.watch(apiDioProvider),
              onSyncError: (error) => ref
                  .read(apiErrorReporterProvider.notifier)
                  .report('收藏同步失败', error),
            )
          : LocalFavoriteRepository(ref.watch(localStoreProvider));
  }
  ref.onDispose(() {
    if (repo is LocalFavoriteRepository) {
      repo.dispose();
    } else if (repo is HttpFavoriteRepository) {
      repo.dispose();
    }
  });
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
  final cfg = ref.watch(appConfigProvider);
  final HistoryRepository repo;
  switch (cfg.dataSource) {
    case DataSource.llm:
    case DataSource.http:
      repo = cfg.dataSource == DataSource.http
          ? HttpHistoryRepository(
              ref.watch(apiDioProvider),
              onSyncError: (error) => ref
                  .read(apiErrorReporterProvider.notifier)
                  .report('历史同步失败', error),
            )
          : LocalHistoryRepository(ref.watch(localStoreProvider));
  }
  ref.onDispose(() {
    if (repo is LocalHistoryRepository) {
      repo.dispose();
    } else if (repo is HttpHistoryRepository) {
      repo.dispose();
    }
  });
  return repo;
});

final searchHistoryProvider = StreamProvider<List<SearchHistoryItem>>((ref) {
  return ref.watch(historyRepositoryProvider).watch();
});

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  final cfg = ref.watch(appConfigProvider);
  return switch (cfg.dataSource) {
    DataSource.http => HttpFeedbackRepository(ref.watch(apiDioProvider)),
    DataSource.llm => MockFeedbackRepository(),
  };
});
