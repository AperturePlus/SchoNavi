import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/config/app_config.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/competition.dart';
import 'package:scho_navi/domain/entities/user_profile.dart';
import 'package:scho_navi/domain/repositories/profile_extraction_repository.dart';
import 'package:scho_navi/features/profile/widgets/achievements_editor.dart';

class _FakeExtract implements ProfileExtractionRepository {
  @override
  Future<Result<AchievementDraft>> extract({required String rawText}) async =>
      const Success(
        AchievementDraft(
          competitions: [Competition(name: '挑战杯', award: '一等奖')],
        ),
      );
}

class _PendingExtract implements ProfileExtractionRepository {
  final completer = Completer<Result<AchievementDraft>>();
  int calls = 0;

  @override
  Future<Result<AchievementDraft>> extract({required String rawText}) {
    calls++;
    return completer.future;
  }
}

void main() {
  testWidgets('AI 整理把抽取结果合并进 profile', (tester) async {
    UserProfile current = const UserProfile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileExtractionRepositoryProvider.overrideWithValue(_FakeExtract()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: AchievementsEditor(
                  value: current,
                  onChanged: (p) => setState(() => current = p),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('achievements-raw')), '挑战杯一等奖');
    await tester.tap(find.text('AI 整理成条目'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(current.competitions.any((c) => c.name == '挑战杯'), isTrue);
  });

  testWidgets('AI 整理加载时显示按钮内转圈并禁用重复提交', (tester) async {
    final fake = _PendingExtract();
    UserProfile current = const UserProfile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileExtractionRepositoryProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: AchievementsEditor(
                  value: current,
                  onChanged: (p) => setState(() => current = p),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('achievements-raw')), '挑战杯一等奖');
    await tester.tap(find.text('AI 整理成条目'));
    await tester.pump();

    expect(fake.calls, 1);
    expect(find.text('AI 正在整理'), findsOneWidget);
    expect(find.text('AI 整理成条目'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('AI 正在整理'));
    await tester.pump();
    expect(fake.calls, 1);

    fake.completer.complete(
      const Success(
        AchievementDraft(
          competitions: [Competition(name: '挑战杯', award: '一等奖')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(current.competitions.any((c) => c.name == '挑战杯'), isTrue);
  });

  testWidgets('HTTP 模式下 AI 整理按钮可用并合并抽取结果', (tester) async {
    UserProfile current = const UserProfile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialAppConfigProvider.overrideWithValue(
            AppConfig.resolve(
              apiKey: '',
              apiBaseUrl: 'https://api.example.com',
            ),
          ),
          profileExtractionRepositoryProvider.overrideWithValue(_FakeExtract()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: AchievementsEditor(
                  value: current,
                  onChanged: (p) => setState(() => current = p),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('AI 整理成条目'), findsOneWidget);
    expect(find.text('AI 整理（需切换到 LLM 模式）'), findsNothing);

    await tester.enterText(find.byKey(const Key('achievements-raw')), '挑战杯一等奖');
    await tester.tap(find.text('AI 整理成条目'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(current.competitions.any((c) => c.name == '挑战杯'), isTrue);
  });
}
