import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/data/dto/feedback_dto.dart';
import 'package:scho_navi/domain/entities/feedback.dart';

void main() {
  final ctx = FeedbackContext(
    route: '/professor/P001',
    sessionId: 's_1',
    messageId: 'm_1',
    professorId: 'P001',
    competitionId: null,
    prompt: '找导师',
    appVersion: '1.2.0',
    dataSourceMode: 'http',
  );
  final feedback = Feedback(
    id: 'id1',
    type: FeedbackType.recommendation,
    content: '推荐了一位做 CV 的老师,但我想要的是 NLP',
    contact: 'user@example.com',
    context: ctx,
    createdAt: DateTime.utc(2026, 6, 30, 12, 0, 0),
  );

  test('fromEntity maps type to snake_case string', () {
    final dto = FeedbackDto.fromEntity(feedback);
    expect(dto.type, 'recommendation');
    expect(dto.context.professorId, 'P001');
    expect(dto.context.competitionId, isNull);
    expect(dto.createdAt, '2026-06-30T12:00:00.000Z');
  });

  test('toJson produces snake_case keys', () {
    final json = FeedbackDto.fromEntity(feedback).toJson();
    expect(json['type'], 'recommendation');
    expect(json['created_at'], '2026-06-30T12:00:00.000Z');
    expect(json['contact'], 'user@example.com');
    expect((json['context'] as Map<String, dynamic>)['session_id'], 's_1');
    expect((json['context'] as Map<String, dynamic>)['competition_id'], isNull);
  });

  test('fromJson round-trips', () {
    final json = FeedbackDto.fromEntity(feedback).toJson();
    final dto = FeedbackDto.fromJson(json);
    expect(dto.id, 'id1');
    expect(dto.type, 'recommendation');
    expect(dto.content, '推荐了一位做 CV 的老师,但我想要的是 NLP');
    expect(dto.context.route, '/professor/P001');
  });

  test('all FeedbackType values map to expected strings', () {
    for (final type in FeedbackType.values) {
      final f = Feedback(
        id: 'x',
        type: type,
        content: 'c',
        contact: null,
        context: const FeedbackContext(),
        createdAt: DateTime.utc(2026, 6, 30),
      );
      expect(FeedbackDto.fromEntity(f).type, switch (type) {
        FeedbackType.recommendation => 'recommendation',
        FeedbackType.missingProfessor => 'missing_professor',
        FeedbackType.bug => 'bug',
        FeedbackType.other => 'other',
      });
    }
  });

  test('默认 FeedbackContext 序列化为 data_source_mode: http', () {
    final f = Feedback(
      id: 'x',
      type: FeedbackType.other,
      content: 'c',
      contact: null,
      context: const FeedbackContext(),
      createdAt: DateTime.utc(2026, 6, 30),
    );
    final json = FeedbackDto.fromEntity(f).toJson();
    final contextJson = json['context'] as Map<String, dynamic>;
    expect(contextJson['data_source_mode'], 'http');
  });

  test('fromJson 缺省 data_source_mode 时回退为 http', () {
    final dto = FeedbackContextDto.fromJson({'app_version': '1.0.0'});
    expect(dto.dataSourceMode, 'http');
  });
}
