import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/fork_ref.dart';
import 'package:scho_navi/features/chat/widgets/professor_anchor_bar.dart';

ForkRef _ref() => ForkRef(
  forkId: 'f_s1_p1',
  mainSessionId: 's1',
  professorId: 'p1',
  professorName: '李卫国',
  university: '清华大学',
  college: '计算机系',
  createdAt: DateTime(2026, 6, 27),
);

void main() {
  testWidgets('渲染头像姓氏 + 姓名 + 学校', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfessorAnchorBar(anchor: _ref(), onTap: () {}),
        ),
      ),
    );
    expect(find.text('李'), findsOneWidget);
    expect(find.text('李卫国 教授'), findsOneWidget);
    expect(find.text('清华大学 · 计算机系'), findsOneWidget);
    expect(find.text('追问中'), findsOneWidget);
  });

  testWidgets('点击触发 onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfessorAnchorBar(anchor: _ref(), onTap: () => tapped = true),
        ),
      ),
    );
    await tester.tap(find.byType(ProfessorAnchorBar));
    expect(tapped, isTrue);
  });

  testWidgets('导师信息不可用时不拼接教授头衔', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfessorAnchorBar(
            anchor: ForkRef(
              forkId: 'f1',
              mainSessionId: 's1',
              professorId: 'missing',
              professorName: forkProfessorUnavailableLabel,
              university: '',
              college: null,
              createdAt: DateTime(2026, 6, 27),
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text(forkProfessorUnavailableLabel), findsOneWidget);
    expect(find.text('$forkProfessorUnavailableLabel 教授'), findsNothing);
  });
}
