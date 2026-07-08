import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/competition_query_understanding.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/recommended_competition.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/competition_recommendation_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/domain/repositories/profile_repository.dart';
import 'package:scho_navi/features/competition_recommendation/providers/competition_home_notifier.dart';

class _FakeRepo implements CompetitionRecommendationRepository {
  _FakeRepo(this._outcome);
  final Result<CompetitionRecommendationResult> _outcome;
  int calls = 0;
  String? lastSessionId;
  @override
  Future<Result<CompetitionRecommendationResult>> getRecommendations({
    required String prompt,
    UserProfile? profile,
    String? sessionId,
  }) async {
    calls++;
    lastSessionId = sessionId;
    return _outcome;
  }
}

class _FakeProfileRepo implements ProfileRepository {
  @override
  UserProfile load() => const UserProfile();

  @override
  Future<UserProfile> refresh() async => load();

  @override
  Future<void> save(UserProfile profile) async {}

  @override
  Future<void> clear() async {}
}

class _FakeHistoryRepo implements HistoryRepository {
  int competitionWrites = 0;
  String? lastCompetitionPrompt;
  CompetitionRecommendationResult? lastCompetitionResult;

  @override
  List<SearchHistoryItem> list() => [];

  @override
  Stream<List<SearchHistoryItem>> watch() => Stream.value(const []);

  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async => null;

  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {}

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {
    competitionWrites++;
    lastCompetitionPrompt = prompt;
    lastCompetitionResult = result;
  }

  @override
  Future<void> remove(String sessionId) async {}

  @override
  Future<void> clear() async {}
}

CompetitionRecommendationResult _result(int n, {String sessionId = 's1'}) =>
    CompetitionRecommendationResult(
      sessionId: sessionId,
      understanding: const CompetitionQueryUnderstanding(
        directions: [],
        categories: [],
        timingPreferences: [],
        teamPreferences: [],
        uncertainties: [],
      ),
      recommendations: List.generate(
        n,
        (i) => RecommendedCompetition(
          id: 'c$i',
          name: 'C$i',
          category: '计算机类',
          level: '国家级',
          tags: const [],
          teamSize: '个人',
          signupTime: '',
          contestTime: '',
          format: '',
          organizer: '',
          officialUrl: null,
          reason: '',
          preparationTips: const [],
          limitations: const [],
          matchScore: 0.5,
        ),
      ),
      followUpQuestions: const [],
    );

ProviderContainer _container(Result<CompetitionRecommendationResult> outcome) {
  return ProviderContainer(
    overrides: [
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
      historyRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
      competitionRecommendationRepositoryProvider.overrideWithValue(
        _FakeRepo(outcome),
      ),
    ],
  );
}

void main() {
  test('submit 成功进入 result', () async {
    final container = _container(Success(_result(2)));
    addTearDown(container.dispose);
    await container.read(competitionHomeProvider.notifier).submit('我想参加算法竞赛');
    final s = container.read(competitionHomeProvider);
    expect(s, isA<CompetitionHomeResult>());
    expect((s as CompetitionHomeResult).data.recommendations.length, 2);
  });

  test('submit 传入非空 c_ sessionId', () async {
    final repo = _FakeRepo(Success(_result(1)));
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        historyRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
        competitionRecommendationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(competitionHomeProvider.notifier).submit('算法竞赛');

    expect(repo.lastSessionId, isNotNull);
    expect(repo.lastSessionId, startsWith('c_'));
    expect(repo.lastSessionId, isNot(contains('-')));
    expect(repo.lastSessionId!.length, 34);
    expect(repo.lastSessionId, matches(RegExp(r'^c_[0-9a-f]{32}$')));
  });

  test('历史保存使用服务端返回的非空 sessionId', () async {
    final history = _FakeHistoryRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        historyRepositoryProvider.overrideWithValue(history),
        competitionRecommendationRepositoryProvider.overrideWithValue(
          _FakeRepo(Success(_result(1, sessionId: 'server_c_1'))),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(competitionHomeProvider.notifier).submit('算法竞赛');

    expect(history.competitionWrites, 1);
    expect(history.lastCompetitionPrompt, '算法竞赛');
    expect(history.lastCompetitionResult?.sessionId, 'server_c_1');
  });

  test('历史保存对空 sessionId 使用本次请求 sessionId 兜底', () async {
    final repo = _FakeRepo(Success(_result(1, sessionId: '   ')));
    final history = _FakeHistoryRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        historyRepositoryProvider.overrideWithValue(history),
        competitionRecommendationRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    await container.read(competitionHomeProvider.notifier).submit('算法竞赛');

    expect(history.lastCompetitionResult?.sessionId, repo.lastSessionId);
    expect(history.lastCompetitionResult?.sessionId, startsWith('c_'));
    expect(history.lastCompetitionResult?.sessionId, isNot(contains('-')));
    expect(history.lastCompetitionResult?.sessionId.length, 34);
    expect(
      history.lastCompetitionResult?.sessionId,
      matches(RegExp(r'^c_[0-9a-f]{32}$')),
    );
    final state = container.read(competitionHomeProvider);
    expect((state as CompetitionHomeResult).data.sessionId, '   ');
  });

  test('空结果进入 empty', () async {
    final container = _container(Success(_result(0)));
    addTearDown(container.dispose);
    await container.read(competitionHomeProvider.notifier).submit('x');
    expect(
      container.read(competitionHomeProvider),
      isA<CompetitionHomeEmpty>(),
    );
  });

  test('失败进入 error', () async {
    final container = _container(const Failure(UnknownException()));
    addTearDown(container.dispose);
    await container.read(competitionHomeProvider.notifier).submit('x');
    expect(
      container.read(competitionHomeProvider),
      isA<CompetitionHomeError>(),
    );
  });

  test('reset 回到 idle', () async {
    final container = _container(Success(_result(1)));
    addTearDown(container.dispose);
    await container.read(competitionHomeProvider.notifier).submit('x');
    container.read(competitionHomeProvider.notifier).reset();
    expect(container.read(competitionHomeProvider), isA<CompetitionHomeIdle>());
  });

  test('竞态：后一次 submit 覆盖前一次', () async {
    final slow = _FakeRepo(Success(_result(1)));
    final fakeHistory = _FakeHistoryRepo();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(_FakeProfileRepo()),
        historyRepositoryProvider.overrideWithValue(fakeHistory),
        competitionRecommendationRepositoryProvider.overrideWithValue(slow),
      ],
    );
    addTearDown(container.dispose);
    await container.read(competitionHomeProvider.notifier).submit('a');
    await container.read(competitionHomeProvider.notifier).submit('b');
    expect(
      container.read(competitionHomeProvider),
      isA<CompetitionHomeResult>(),
    );
    expect(slow.calls, 2);
  });
}
