import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/professor.dart';
import 'package:scho_navi/domain/repositories/professor_repository.dart';
import 'package:scho_navi/features/professor/pages/professor_page.dart';

import 'package:scho_navi/core/router/app_router.dart';
import '../../helpers/stub_api_dio.dart';

class _FakeRepo implements ProfessorRepository {
  @override
  Future<Result<Professor>> getProfessor(String id) async =>
      const Success(_professor);
}

const _professor = Professor(
  id: 'p_001',
  name: '张三',
  university: '上海交通大学',
  college: '电子信息与电气工程学院',
  title: '教授',
  researchFields: ['医学影像'],
  bio: '研究医学影像。',
);

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp.router(routerConfig: container.read(routerProvider)),
);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'seenOnboarding': true,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      professorRepositoryProvider.overrideWithValue(_FakeRepo()),
      dioProvider.overrideWithValue(stubDio()),
      apiIdentityDioProvider.overrideWithValue(stubDio()),
    ],
  );
}

void main() {
  testWidgets('/professor/:id 把 fork 来源参数传给 ProfessorPage', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final router = container.read(routerProvider);
    router.go('/professor/p_001?msid=main_sid_123&stid=turn_1&fid=fork_1');
    await tester.pumpAndSettle();

    final page = tester.widget<ProfessorPage>(find.byType(ProfessorPage));
    expect(page.professorId, 'p_001');
    expect(page.mainSessionId, 'main_sid_123');
    expect(page.sourceTurnId, 'turn_1');
    expect(page.forkId, 'fork_1');
  });

  testWidgets('/professor/:id 没有 msid 时 mainSessionId 为 null', (tester) async {
    final container = await _container();
    addTearDown(container.dispose);

    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    final router = container.read(routerProvider);
    router.go('/professor/p_001');
    await tester.pumpAndSettle();

    final page = tester.widget<ProfessorPage>(find.byType(ProfessorPage));
    expect(page.professorId, 'p_001');
    expect(page.mainSessionId, isNull);
  });
}
