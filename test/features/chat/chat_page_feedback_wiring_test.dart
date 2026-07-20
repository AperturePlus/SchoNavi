import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scho_navi/core/di/providers.dart';
import 'package:scho_navi/core/error/app_exception.dart';
import 'package:scho_navi/core/result/result.dart';
import 'package:scho_navi/domain/entities/feedback.dart';
import 'package:scho_navi/domain/repositories/feedback_repository.dart';
import 'package:scho_navi/features/feedback/providers/feedback_provider.dart';

/// 记录每次提交的 Feedback，供断言 type/content/context 字段。
class _RecordingFeedbackRepo implements FeedbackRepository {
  _RecordingFeedbackRepo(this.submitted);

  final List<Feedback> submitted;

  @override
  Future<Result<void>> submit(Feedback feedback) async {
    submitted.add(feedback);
    return const Success(null);
  }
}

class _FailFeedbackRepo implements FeedbackRepository {
  @override
  Future<Result<void>> submit(Feedback feedback) async =>
      const Failure(ValidationException('boom'));
}

void main() {
  test('submit 提交 recommendation 类型并携带 context 字段到 repository', () async {
    final submitted = <Feedback>[];
    final container = ProviderContainer(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(
          _RecordingFeedbackRepo(submitted),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(feedbackSubmitProvider.notifier);

    final ok = await notifier.submit(
      type: FeedbackType.recommendation,
      content: '推荐不准：方向对不上',
      context: FeedbackContext(
        professorId: 'p_1',
        sessionId: 's1',
        prompt: '问',
      ).copyWith(appVersion: '0.1.0', dataSourceMode: 'http'),
    );

    expect(ok, isTrue);
    expect(submitted, hasLength(1));
    final fb = submitted.last;
    expect(fb.type, FeedbackType.recommendation);
    expect(fb.content, '推荐不准：方向对不上');
    expect(fb.context.professorId, 'p_1');
    expect(fb.context.sessionId, 's1');
    expect(fb.context.prompt, '问');
    expect(fb.context.appVersion, '0.1.0');
    expect(fb.context.dataSourceMode, 'http');
    expect(fb.id, isNotEmpty);
  });

  test('submit 提交 other 类型并把空文字替换为占位文案', () async {
    final submitted = <Feedback>[];
    final container = ProviderContainer(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(
          _RecordingFeedbackRepo(submitted),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(feedbackSubmitProvider.notifier);

    final ok = await notifier.submit(
      type: FeedbackType.other,
      content: '点踩反馈（无文字）',
      context: FeedbackContext(
        messageId: 'm_1',
        sessionId: 's2',
      ).copyWith(appVersion: '0.1.0', dataSourceMode: 'http'),
    );

    expect(ok, isTrue);
    expect(submitted, hasLength(1));
    final fb = submitted.last;
    expect(fb.type, FeedbackType.other);
    expect(fb.content, '点踩反馈（无文字）');
    expect(fb.context.messageId, 'm_1');
    expect(fb.context.sessionId, 's2');
    expect(fb.context.appVersion, '0.1.0');
    expect(fb.context.dataSourceMode, 'http');
  });

  test('submit 失败时 repository 报错则返回 false 且不抛', () async {
    final container = ProviderContainer(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(_FailFeedbackRepo()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(feedbackSubmitProvider.notifier);

    final ok = await notifier.submit(
      type: FeedbackType.recommendation,
      content: '推荐不准',
      context: FeedbackContext(professorId: 'p_2'),
    );

    expect(ok, isFalse);
    final state = container.read(feedbackSubmitProvider);
    expect(state.success, isFalse);
    expect(state.errorMessage, 'boom');
  });
}
