import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/domain/entities/feedback.dart';

void main() {
  group('FeedbackContext.fromQuery', () {
    test('decodes known query keys', () {
      final ctx = FeedbackContext.fromQuery(const {
        'route': '/professor/P001',
        'sid': 's_1',
        'mid': 'm_1',
        'pid': 'P001',
        'cid': 'C_1',
        'prompt': '找导师',
        'v': '1.2.0',
        'mode': 'http',
      });
      expect(ctx.route, '/professor/P001');
      expect(ctx.sessionId, 's_1');
      expect(ctx.messageId, 'm_1');
      expect(ctx.professorId, 'P001');
      expect(ctx.competitionId, 'C_1');
      expect(ctx.prompt, '找导师');
      expect(ctx.appVersion, '1.2.0');
      expect(ctx.dataSourceMode, 'http');
    });

    test('empty query yields null optional fields', () {
      final ctx = FeedbackContext.fromQuery(const {});
      expect(ctx.route, isNull);
      expect(ctx.sessionId, isNull);
      expect(ctx.appVersion, '');
      expect(ctx.dataSourceMode, FeedbackContext.defaultDataSourceMode);
    });
  });

  test('Feedback.copyWith preserves identity when unchanged', () {
    final f = Feedback(
      id: 'id1',
      type: FeedbackType.bug,
      content: '崩溃了',
      contact: null,
      context: FeedbackContext.fromQuery(const {}),
      createdAt: DateTime.utc(2026, 6, 30),
    );
    expect(f.copyWith().id, 'id1');
    expect(f.copyWith(type: FeedbackType.other).type, FeedbackType.other);
  });

  test('默认构造的 FeedbackContext 使用 HTTP 数据源模式', () {
    const ctx = FeedbackContext();
    expect(ctx.dataSourceMode, FeedbackContext.defaultDataSourceMode);
    expect(ctx.dataSourceMode, 'http');
  });
}
