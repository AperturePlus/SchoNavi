import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/chat/pages/chat_page.dart';
import '../../features/compare/pages/compare_page.dart';
import '../../features/competition_recommendation/pages/competition_detail_page.dart';
import '../../features/email/pages/email_page.dart';
import '../../features/feedback/pages/feedback_page.dart';
import '../../features/favorite/pages/favorite_page.dart';
import '../../features/history/pages/history_page.dart';
import '../../features/home/pages/home_page.dart';
import '../../features/match/pages/match_page.dart';
import '../../features/onboarding/pages/onboarding_page.dart';
import '../../features/preparation/pages/preparation_plan_detail_page.dart';
import '../../features/preparation/pages/preparation_plan_form_page.dart';
import '../../features/preparation/pages/preparation_plans_page.dart';
import '../../features/preparation/pages/today_tasks_page.dart';
import '../../features/professor/pages/professor_page.dart';
import '../../features/profile/pages/privacy_agreement_page.dart';
import '../../features/profile/pages/profile_intro_page.dart';
import '../../features/profile/pages/profile_page.dart';
import '../../features/profile/pages/profile_wizard_page.dart';
import '../../features/settings/pages/settings_page.dart';
import '../../domain/entities/feedback.dart';
import '../../domain/entities/preparation_plan.dart';

import '../di/providers.dart';
import '../error/app_exception.dart';
import '../motion/page_transition.dart';
import '../../shared/widgets/error_view.dart';

FeedbackType? _parseFeedbackType(String? raw) {
  switch (raw) {
    case 'recommendation':
      return FeedbackType.recommendation;
    case 'missing_professor':
      return FeedbackType.missingProfessor;
    case 'bug':
      return FeedbackType.bug;
    case 'other':
      return FeedbackType.other;
    default:
      return null;
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    redirect: (context, state) {
      final seen =
          ref.read(localStoreProvider).getBool(OnboardingPage.seenKey) ?? false;
      final atOnboarding = state.matchedLocation == '/onboarding';
      if (!seen && !atOnboarding) return '/onboarding';
      if (seen && atOnboarding) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(
        path: '/home',
        builder: (_, state) {
          final tab = state.uri.queryParameters['tab'];
          return HomePage(
            initialTab: tab == 'competition'
                ? HomeTab.competition
                : HomeTab.mentor,
            historySessionId: state.uri.queryParameters['historySid'],
          );
        },
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const ProfilePage()),
      ),
      GoRoute(
        path: '/favorites',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const FavoritePage()),
      ),
      GoRoute(
        path: '/history',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const HistoryPage()),
      ),
      GoRoute(
        path: '/competition/:id',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: CompetitionDetailPage(
            competitionId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/professor/:id',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: ProfessorPage(
            professorId: state.pathParameters['id']!,
            mainSessionId: state.uri.queryParameters['msid'],
            sourceTurnId: state.uri.queryParameters['stid'],
            forkId: state.uri.queryParameters['fid'],
          ),
        ),
      ),
      GoRoute(
        path: '/feedback',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: FeedbackPage(
            type: _parseFeedbackType(state.uri.queryParameters['type']),
            context: FeedbackContext.fromQuery(state.uri.queryParameters),
          ),
        ),
      ),
      GoRoute(
        path: '/chat',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: ChatPage(
            sessionId: state.uri.queryParameters['sid'],
            professorId: state.uri.queryParameters['pid'],
            initialPrompt: state.uri.queryParameters['q'],
            forkMode: state.uri.queryParameters['fork'] == 'true',
            mainSessionId: state.uri.queryParameters['msid'],
            forkId: state.uri.queryParameters['fid'],
            sourceTurnId: state.uri.queryParameters['stid'],
          ),
        ),
      ),
      GoRoute(
        path: '/email',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: EmailPage(professorId: state.uri.queryParameters['pid'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/compare',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: ComparePage(
            ids: (state.uri.queryParameters['ids'] ?? '')
                .split(',')
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .toList(),
          ),
        ),
      ),
      GoRoute(
        path: '/match',
        pageBuilder: (_, state) => sharedAxisPage(
          state: state,
          child: MatchPage(professorId: state.uri.queryParameters['pid'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/preparation-plans',
        pageBuilder: (context, state) =>
            sharedAxisPage(state: state, child: const PreparationPlansPage()),
      ),
      GoRoute(
        path: '/preparation-plans/today',
        pageBuilder: (context, state) =>
            sharedAxisPage(state: state, child: const TodayTasksPage()),
      ),
      // 静态 `new` 路径必须注册在 `:id` 之前，否则会被参数路由吞掉。
      GoRoute(
        path: '/preparation-plans/new',
        pageBuilder: (context, state) => sharedAxisPage(
          state: state,
          child: _PreparationPlanFormRoute(
            competitionId: state.uri.queryParameters['competitionId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/preparation-plans/:id',
        pageBuilder: (context, state) => sharedAxisPage(
          state: state,
          child: PreparationPlanDetailPage(planId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/profile/privacy',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const PrivacyAgreementPage()),
      ),
      GoRoute(
        path: '/profile/intro',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const ProfileIntroPage()),
      ),
      GoRoute(
        path: '/profile/wizard',
        pageBuilder: (_, state) =>
            sharedAxisPage(state: state, child: const ProfileWizardPage()),
      ),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
    ],
  );
});

/// `/preparation-plans/new?competitionId=...` 的路由壳：从竞赛目录取基底
/// 构造 [CompetitionSnapshot] 后渲染 [PreparationPlanFormPage]；查不到则
/// 展示空态（避免把空 snapshot 喂给表单生成器）。
class _PreparationPlanFormRoute extends ConsumerWidget {
  const _PreparationPlanFormRoute({required this.competitionId});

  final String competitionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (competitionId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('创建备赛计划')),
        body: const Center(child: Text('缺少竞赛信息')),
      );
    }
    final baseAsync = ref.watch(competitionByIdProvider(competitionId));
    return baseAsync.when(
      data: (base) {
        if (base == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('创建备赛计划')),
            body: const Center(child: Text('未找到该竞赛')),
          );
        }
        return PreparationPlanFormPage(
          competition: CompetitionSnapshot(
            id: base.id,
            name: base.name,
            category: base.category,
            rulesSummary: CompetitionRulesSummary(
              signupTime: base.signupTime,
              contestTime: base.contestTime,
              teamSize: base.teamSize,
              format: base.format,
              organizer: base.organizer,
              officialUrl: base.officialUrl,
            ),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('创建备赛计划')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(title: const Text('创建备赛计划')),
        body: ErrorView(
          error: normalizeAppException(error, stackTrace),
          onRetry: () => ref.invalidate(competitionByIdProvider(competitionId)),
        ),
      ),
    );
  }
}
