import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final openApi = File('docs/openapi.yaml');

  test('OpenAPI documents chat quick actions endpoint', () {
    final text = openApi.readAsStringSync();

    expect(text, contains('  /chat/quick-actions:'));
    expect(text, contains(r"$ref: '#/components/schemas/QuickActionsRequest'"));
    expect(
      text,
      contains(r"$ref: '#/components/schemas/QuickActionsEnvelope'"),
    );
  });

  test('protected endpoints declare bearer and cookie security', () {
    final text = openApi.readAsStringSync();

    for (final path in [
      '/recommendations/mentors',
      '/chat/quick-actions',
      '/profile',
      '/favorites',
      '/history',
      '/feedback',
      '/preparation/config',
      '/preparation-templates',
      '/preparation-plans/generate',
    ]) {
      final index = text.indexOf('  $path:');
      expect(index, isNonNegative, reason: '$path missing from OpenAPI');
      final next = text.indexOf('\n  /', index + 1);
      final block = text.substring(index, next == -1 ? text.length : next);
      expect(block, contains('security:'), reason: '$path lacks security');
      expect(block, contains('bearerAuth: []'));
      expect(block, contains('cookieAuth: []'));
    }
  });

  test('OpenAPI documents Flutter HTTP production paths', () {
    final text = openApi.readAsStringSync();

    for (final path in [
      '/home/config',
      '/home/prompts',
      '/competitions',
      '/competitions/{competition_id}',
      '/recommendations/mentors',
      '/recommendations/competitions',
      '/chat/route',
      '/chat/quick-actions',
      '/preparation/config',
      '/preparation-templates',
      '/preparation-plans/generate',
      '/preparation-plans/diagnose',
      '/feedback',
    ]) {
      expect(text, contains('  $path:'), reason: '$path missing from OpenAPI');
    }
  });

  test('API contract requires echoed request correlation IDs', () {
    final openApiText = openApi.readAsStringSync();
    final contractText = File('docs/api-contract.md').readAsStringSync();

    expect(openApiText, contains('Every request sends X-Request-ID'));
    expect(openApiText, contains('RequestId:'));
    expect(openApiText, contains('RequestIdHeader:'));
    expect(openApiText, contains('format: uuid'));
    expect(contractText, contains('X-Request-ID: <uuid-v7>'));
    expect(contractText, contains('Access-Control-Expose-Headers'));

    final pathCount = RegExp(
      r'^  /',
      multiLine: true,
    ).allMatches(openApiText).length;
    final requestHeaderCount = RegExp(
      r"\$ref: '#/components/parameters/RequestIdHeader'",
    ).allMatches(openApiText).length;
    final successCount = RegExp(
      r"^        '200':$",
      multiLine: true,
    ).allMatches(openApiText).length;
    final responseHeaderCount = RegExp(
      r'^\s+X-Request-ID:$',
      multiLine: true,
    ).allMatches(openApiText).length;

    expect(requestHeaderCount, pathCount);
    expect(responseHeaderCount, successCount);
  });

  test('OpenAPI uses Dart timeline enum names', () {
    final text = openApi.readAsStringSync();

    expect(text, contains('enum: [eventWindow, submission]'));
    expect(text, isNot(contains('enum: [event_window, submission]')));
  });

  test('OpenAPI documents user feedback endpoint', () {
    final text = openApi.readAsStringSync();

    expect(text, contains('  /feedback:'));
    expect(text, isNot(contains('  /api/v1/feedback:')));
    expect(text, contains(r"$ref: '#/components/schemas/UserFeedbackRequest'"));
    expect(
      text,
      contains(r"$ref: '#/components/schemas/UserFeedbackEnvelope'"),
    );
  });
}
