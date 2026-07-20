import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scho_navi/features/preparation/providers/preparation_reminder_providers.dart';
import 'package:scho_navi/main.dart';

void main() {
  test('notificationActionMain registers handler without runApp', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // SharedPreferencesLocalStore.getJsonList reads via getString + jsonDecode,
    // so the mock value must be a JSON-encoded string (not a raw list).
    SharedPreferences.setMockInitialValues({
      'competition_preparation_plans.v2': jsonEncode([
        {
          'id': 'p1',
          'competition': {
            'id': 'c1',
            'name': 'X',
            'category': '计算机类',
            'rules_summary': {
              'signup_time': '',
              'contest_time': '',
              'team_size': '',
              'format': '',
              'organizer': '',
            },
          },
          'target_date': '2026-08-15T00:00:00.000',
          'timeline_type': 'submission',
          'revision': 0,
          'weekly_commitment': 'hours6to10',
          'experience_level': 'beginner',
          'status': 'active',
          'phases': [
            {
              'key': 'p',
              'title': '阶段',
              'start_date': '2026-06-01T00:00:00.000',
              'end_date': '2026-07-31T00:00:00.000',
              'tasks': [
                {
                  'id': 't1',
                  'title': 't1',
                  'kind': 'required',
                  'estimated_hours': 1,
                  'due_date': '2026-07-02T00:00:00.000',
                },
              ],
            },
          ],
          'created_at': '2026-06-01T00:00:00.000',
          'updated_at': '2026-06-01T00:00:00.000',
          'tight_schedule': false,
          'overload': false,
        },
      ]),
    });

    await notificationActionMain();

    // Simulate the Android native side invoking the channel: deliver a platform
    // message and decode the reply produced by the Dart handler above.
    final result = await _invokeChannelFromPlatform(
      'completeNotificationTask',
      {'planId': 'p1', 'taskId': 't1'},
    );
    expect((result as Map)['status'], 'completed');
  });
}

Future<dynamic> _invokeChannelFromPlatform(
  String method,
  Map<String, dynamic> args,
) {
  const codec = StandardMethodCodec();
  final data = codec.encodeMethodCall(MethodCall(method, args));
  final completer = Completer<dynamic>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(notificationActionChannel.name, data, (
        ByteData? reply,
      ) {
        if (reply == null) {
          completer.complete(null);
          return;
        }
        completer.complete(codec.decodeEnvelope(reply));
      });
  return completer.future;
}
