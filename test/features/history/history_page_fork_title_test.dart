import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/conversation_session.dart';
import 'package:scho_navi/domain/repositories/conversation_repository.dart';
import 'package:scho_navi/features/history/pages/history_page.dart';

import '../../helpers/fake_conversation_repository.dart';

/// 仅提供 listSessions / listForks 的最小 fake，供历史页展开分支断言标题。
class _HistoryRepo implements ConversationRepository {
  _HistoryRepo(this._forks);

  final List<ConversationSession> _forks;

  @override
  Future<Result<List<ConversationSession>>> listSessions() async =>
      Success([_rootSession]);

  @override
  Future<Result<List<ConversationSession>>> listForks(
    String rootSessionId,
  ) async =>
      Success(_forks.where((f) => f.rootSessionId == rootSessionId).toList());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  static final ConversationSession _rootSession = fakeSession(
    id: 'root-1',
    kind: ConversationSessionKind.general,
    title: '主会话',
  );
}

ConversationSession _fork({
  required String id,
  String? title,
  String rootSessionId = 'root-1',
}) => fakeSession(
  id: id,
  kind: ConversationSessionKind.fork,
  rootSessionId: rootSessionId,
  professorId: 'p_$id',
  title: title,
);

Widget _wrap(ConversationRepository repo) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => const HistoryPage())],
  );
  return ProviderScope(
    overrides: [conversationRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('展开分支显示各 fork 的 title', (tester) async {
    final repo = _HistoryRepo([
      _fork(id: 'f1', title: '张三教授'),
      _fork(id: 'f2', title: '李四教授'),
    ]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text('张三教授'), findsOneWidget);
    expect(find.text('李四教授'), findsOneWidget);
  });

  testWidgets('fork title 为 null 时回退为「导师追问」', (tester) async {
    final repo = _HistoryRepo([_fork(id: 'f1', title: null)]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text('导师追问'), findsOneWidget);
  });

  testWidgets('fork title 为空白时回退为「导师追问」', (tester) async {
    final repo = _HistoryRepo([_fork(id: 'f1', title: '   ')]);
    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('查看分支'));
    await tester.pumpAndSettle();

    expect(find.text('导师追问'), findsOneWidget);
  });
}
