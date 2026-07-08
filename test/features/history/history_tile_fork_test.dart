import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/data/mock/mock_db.dart';
import 'package:scho_navi/domain/entities/chat_message.dart';
import 'package:scho_navi/domain/entities/competition_recommendation_result.dart';
import 'package:scho_navi/domain/entities/conversation_aggregate.dart';
import 'package:scho_navi/domain/entities/conversation_event.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/entities/recommendation_result.dart';
import 'package:scho_navi/domain/entities/search_history_item.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/domain/repositories/history_repository.dart';
import 'package:scho_navi/features/history/pages/history_page.dart';

class _FakeHistoryRepo implements HistoryRepository {
  final _items = <SearchHistoryItem>[];

  @override
  List<SearchHistoryItem> list() => List.unmodifiable(_items);

  @override
  Stream<List<SearchHistoryItem>> watch() => Stream.value(list());

  @override
  Future<SearchHistoryItem?> getBySessionId(
    String sessionId, {
    SearchHistoryType? type,
  }) async {
    for (final item in _items) {
      if (item.sessionId == sessionId && (type == null || item.type == type)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> addFromResult({
    required String prompt,
    required RecommendationResult result,
  }) async {}

  @override
  Future<void> addFromCompetitionResult({
    required String prompt,
    required CompetitionRecommendationResult result,
  }) async {}

  @override
  Future<void> remove(String sessionId) async {
    _items.removeWhere((item) => item.sessionId == sessionId);
  }

  @override
  Future<void> clear() async {
    _items.clear();
  }
}

class _FakeConversationRepo implements ConversationRepository {
  _FakeConversationRepo({
    required List<ConversationSession> sessions,
    Map<String, List<ConversationSession>> forks = const {},
  }) : _sessions = List.of(sessions),
       _forks = forks.map(
         (key, value) => MapEntry(key, List<ConversationSession>.of(value)),
       );

  final List<ConversationSession> _sessions;
  final Map<String, List<ConversationSession>> _forks;

  List<ConversationSession> forksFor(String rootSessionId) =>
      List.unmodifiable(_forks[rootSessionId] ?? const []);

  List<ConversationSession> get sessions => List.unmodifiable(_sessions);

  @override
  Future<Result<ConversationSession>> createSession({
    String? professorId,
  }) async => throw UnimplementedError();

  @override
  Future<Result<ConversationAggregate>> loadSession(String sessionId) async =>
      throw UnimplementedError();

  @override
  Future<Result<ConversationSession>> forkSessionAtTurn({
    required String sourceSessionId,
    required String sourceTurnId,
    required String professorId,
  }) async => throw UnimplementedError();

  @override
  Stream<ConversationEvent> submitTurn({
    required String sessionId,
    required String text,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Stream<ConversationEvent> regenerateTurn({
    required String sessionId,
    required String turnId,
    required int expectedRevision,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<Result<void>> cancelAttempt(String attemptId) async =>
      const Success(null);

  @override
  Future<Result<void>> setMessageFeedback(
    String messageId,
    ChatMessageFeedback feedback,
  ) async => const Success(null);

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success(List.unmodifiable(_sessions));

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async => Success(forksFor(rootSessionId));

  @override
  Future<Result<void>> deleteSession(String sessionId) async {
    final rootDeleted = _sessions.any((session) => session.id == sessionId);
    _sessions.removeWhere((session) => session.id == sessionId);
    if (rootDeleted) {
      _forks.remove(sessionId);
    }
    for (final forks in _forks.values) {
      forks.removeWhere(
        (session) =>
            session.id == sessionId || session.rootSessionId == sessionId,
      );
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> clearSessions() async {
    _sessions.clear();
    _forks.clear();
    return const Success(null);
  }
}

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HistoryPage()),
    GoRoute(
      path: '/chat',
      builder: (_, state) => Text('sid=${state.uri.queryParameters['sid']}'),
    ),
  ],
);

Widget _pump(_FakeConversationRepo conversationRepo) {
  final container = ProviderContainer(
    overrides: [
      conversationRepositoryProvider.overrideWithValue(conversationRepo),
      historyRepositoryProvider.overrideWithValue(_FakeHistoryRepo()),
    ],
  );
  addTearDown(container.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: _router()),
  );
}

ConversationSession _root({String id = 's1', String title = '想做CV'}) {
  final now = DateTime.utc(2026, 6, 27);
  return ConversationSession(
    id: id,
    kind: ConversationSessionKind.general,
    rootSessionId: id,
    ownerId: 'local',
    revision: 0,
    title: title,
    createdAt: now,
    updatedAt: now,
  );
}

ConversationSession _fork({
  required String id,
  String rootSessionId = 's1',
  required String professorId,
}) {
  final now = DateTime.utc(2026, 6, 27);
  return ConversationSession(
    id: id,
    kind: ConversationSessionKind.fork,
    rootSessionId: rootSessionId,
    sourceSessionId: rootSessionId,
    sourceTurnId: 'turn-1',
    professorId: professorId,
    ownerId: 'local',
    revision: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('主条目显示会话标题和分支按钮，不显示旧摘要/计数/标签', (tester) async {
    final repo = _FakeConversationRepo(sessions: [_root(title: '想做CV，想去北京')]);

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    expect(find.text('想做CV，想去北京'), findsOneWidget);
    expect(find.byTooltip('查看分支'), findsOneWidget);
    expect(find.textContaining('为你挑'), findsNothing);
    expect(find.textContaining('位导师'), findsNothing);
    expect(find.textContaining('4 位导师'), findsNothing);
  });

  testWidgets('点击分支按钮展开子项并显示导师信息', (tester) async {
    final professor = MockDb().allProfessors.first;
    final repo = _FakeConversationRepo(
      sessions: [_root()],
      forks: {
        's1': [_fork(id: 'fork-1', professorId: professor.id)],
      },
    );

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text(professor.name), findsOneWidget);
    expect(find.byTooltip('收起分支'), findsOneWidget);
  });

  testWidgets('无 fork 展开显示暂无追问分支', (tester) async {
    final repo = _FakeConversationRepo(sessions: [_root()]);

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text('暂无追问分支'), findsOneWidget);
  });

  testWidgets('子项点击导航到 /chat?sid=forkId', (tester) async {
    final professor = MockDb().allProfessors.first;
    final repo = _FakeConversationRepo(
      sessions: [_root()],
      forks: {
        's1': [_fork(id: 'fork-1', professorId: professor.id)],
      },
    );

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(professor.name));
    await tester.pumpAndSettle();

    expect(find.text('sid=fork-1'), findsOneWidget);
  });

  testWidgets('子项左滑删除并刷新 fork 列表', (tester) async {
    final professor = MockDb().allProfessors.first;
    final repo = _FakeConversationRepo(
      sessions: [_root()],
      forks: {
        's1': [_fork(id: 'fork-1', professorId: professor.id)],
      },
    );

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();
    expect(find.text(professor.name), findsOneWidget);

    await tester.drag(find.text(professor.name), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text(professor.name), findsNothing);
    expect(repo.forksFor('s1'), isEmpty);
  });

  testWidgets('主条目左滑级联删除，先删 fork 再去掉主记录', (tester) async {
    final professor = MockDb().allProfessors.first;
    final repo = _FakeConversationRepo(
      sessions: [_root()],
      forks: {
        's1': [_fork(id: 'fork-1', professorId: professor.id)],
      },
    );

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('想做CV'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('想做CV'), findsNothing);
    expect(repo.sessions, isEmpty);
    expect(repo.forksFor('s1'), isEmpty);
  });

  testWidgets('展开两 fork 后删除一个，立即刷新且折叠再展开只剩一个', (tester) async {
    final db = MockDb();
    final prof0 = db.allProfessors[0];
    final prof1 = db.allProfessors[1];
    final repo = _FakeConversationRepo(
      sessions: [_root()],
      forks: {
        's1': [
          _fork(id: 'fork-1', professorId: prof0.id),
          _fork(id: 'fork-2', professorId: prof1.id),
        ],
      },
    );

    await tester.pumpWidget(_pump(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();
    expect(find.text(prof0.name), findsOneWidget);
    expect(find.text(prof1.name), findsOneWidget);

    await tester.drag(find.text(prof0.name), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text(prof0.name), findsNothing);
    expect(find.text(prof1.name), findsOneWidget);

    await tester.tap(find.byTooltip('收起分支'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text(prof0.name), findsNothing);
    expect(find.text(prof1.name), findsOneWidget);
    expect(repo.forksFor('s1').single.professorId, prof1.id);
  });
}
