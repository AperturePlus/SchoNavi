import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/launcher/link_launcher.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/professor.dart';
import 'package:scho_navi/domain/repositories/professor_repository.dart';
import 'package:scho_navi/features/professor/pages/professor_page.dart';

import '../../helpers/fake_favorite_repository.dart';

class _FakeRepo implements ProfessorRepository {
  _FakeRepo(this._result);

  final Result<Professor> _result;

  @override
  Future<Result<Professor>> getProfessor(String id) async => _result;
}

class _FakeLauncher implements LinkLauncher {
  _FakeLauncher(this.result);

  final LaunchResult result;
  String? openedUrl;

  @override
  Future<LaunchResult> open(String? url) async {
    openedUrl = url;
    return result;
  }
}

Future<Widget> _wrap(Result<Professor> result, {LinkLauncher? launcher}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      professorRepositoryProvider.overrideWithValue(_FakeRepo(result)),
      favoriteRepositoryProvider.overrideWithValue(FakeFavoriteRepository()),
      if (launcher != null) linkLauncherProvider.overrideWithValue(launcher),
    ],
    child: const MaterialApp(home: ProfessorPage(professorId: 'p_001')),
  );
}

const _professor = Professor(
  id: 'p_001',
  name: '张三',
  university: '上海交通大学',
  college: '电子信息与电气工程学院',
  title: '教授',
  researchFields: ['医学影像'],
  bio: '研究医学影像。',
  homepageUrl: 'https://example.edu.cn/zhangsan',
);

void main() {
  testWidgets('renders professor info', (tester) async {
    await tester.pumpWidget(await _wrap(const Success(_professor)));
    await tester.pumpAndSettle();
    expect(find.text('张三  教授'), findsOneWidget);
    expect(find.textContaining('研究医学影像'), findsOneWidget);
  });

  testWidgets('shows 暂无信息 for missing bio', (tester) async {
    await tester.pumpWidget(
      await _wrap(
        const Success(
          Professor(
            id: 'p_x',
            name: '李四',
            university: '某大学',
            college: '某学院',
            title: '讲师',
            researchFields: ['网络安全'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('暂无信息'), findsWidgets);
  });

  testWidgets('shows ErrorView on failure', (tester) async {
    await tester.pumpWidget(await _wrap(const Failure(NotFoundException())));
    await tester.pumpAndSettle();
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('favorite button toggles detail page state', (tester) async {
    await tester.pumpWidget(await _wrap(const Success(_professor)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏导师'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('取消收藏'), findsOneWidget);
  });

  testWidgets('homepage button calls injected launcher', (tester) async {
    final launcher = _FakeLauncher(LaunchResult.success);
    await tester.pumpWidget(
      await _wrap(const Success(_professor), launcher: launcher),
    );
    await tester.pumpAndSettle();

    final homepageButton = find.text('访问主页');
    await tester.scrollUntilVisible(homepageButton, 200);
    await tester.tap(homepageButton);
    await tester.pumpAndSettle();

    expect(launcher.openedUrl, 'https://example.edu.cn/zhangsan');
  });

  testWidgets('missing homepage shows noUrl message', (tester) async {
    await tester.pumpWidget(
      await _wrap(
        const Success(
          Professor(
            id: 'p_002',
            name: '李四',
            university: '某大学',
            college: '某学院',
            title: '教授',
            researchFields: ['网络安全'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final homepageButton = find.text('访问主页');
    await tester.scrollUntilVisible(homepageButton, 200);
    await tester.tap(homepageButton);
    await tester.pumpAndSettle();

    expect(find.text('暂无主页信息'), findsOneWidget);
  });

  testWidgets('failed homepage launch shows stale link message', (
    tester,
  ) async {
    await tester.pumpWidget(
      await _wrap(
        const Success(_professor),
        launcher: _FakeLauncher(LaunchResult.failed),
      ),
    );
    await tester.pumpAndSettle();

    final homepageButton = find.text('访问主页');
    await tester.scrollUntilVisible(homepageButton, 200);
    await tester.tap(homepageButton);
    await tester.pumpAndSettle();

    expect(find.text('主页可能已失效，可通过学校官网确认'), findsOneWidget);
  });
}
