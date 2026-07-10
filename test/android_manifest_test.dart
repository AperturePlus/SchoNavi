import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('main Android manifest declares release internet permission', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
    );
  });

  test('main Android manifest declares preparation reminder integration', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
      ),
    );
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>',
      ),
    );
    expect(manifest, contains('android:name=".PreparationWidgetProvider"'));
    expect(
      manifest,
      contains(
        '<action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>',
      ),
    );
    expect(
      manifest,
      contains('android:resource="@xml/preparation_widget_info"'),
    );
    expect(manifest, contains('android:name=".DailyReminderReceiver"'));
    expect(manifest, contains('android:name=".DeadlineAlarmReceiver"'));
    expect(manifest, contains('android:name=".ReminderActionReceiver"'));
    expect(manifest, contains('android:name=".SnoozedTaskReceiver"'));
    expect(manifest, contains('android:name=".ReminderRescheduleReceiver"'));
    expect(
      manifest,
      contains('<action android:name="android.intent.action.BOOT_COMPLETED"/>'),
    );
    expect(
      manifest,
      contains(
        '<action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>',
      ),
    );
    expect(
      manifest,
      contains(
        '<action android:name="android.intent.action.TIMEZONE_CHANGED"/>',
      ),
    );
    expect(
      manifest,
      contains('<action android:name="android.intent.action.DATE_CHANGED"/>'),
    );
  });

  test('values/colors.xml defines widget palette for light mode', () {
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    for (final name in [
      'widget_surface',
      'widget_border',
      'widget_primary',
      'widget_secondary',
      'widget_accent',
      'widget_text_primary',
      'widget_text_secondary',
      'widget_chip',
      'widget_progress_track',
    ]) {
      expect(
        colors,
        contains('name="$name"'),
        reason: 'missing $name in light colors',
      );
    }
  });

  test('four widget layout files exist', () {
    for (final name in [
      'preparation_widget_micro',
      'preparation_widget_small',
      'preparation_widget_wide',
      'preparation_widget_hero',
    ]) {
      final file = File('android/app/src/main/res/layout/$name.xml');
      expect(file.existsSync(), isTrue, reason: 'missing layout $name.xml');
    }
    expect(
      File(
        'android/app/src/main/res/layout/preparation_widget_compact.xml',
      ).existsSync(),
      isFalse,
      reason: 'compact.xml should be removed',
    );
    expect(
      File(
        'android/app/src/main/res/layout/preparation_widget_expanded.xml',
      ).existsSync(),
      isFalse,
      reason: 'expanded.xml should be removed',
    );
  });

  test('widget_info declares resize bounds', () {
    final info = File(
      'android/app/src/main/res/xml/preparation_widget_info.xml',
    ).readAsStringSync();
    expect(info, contains('android:minResizeWidth'));
    expect(info, contains('android:minResizeHeight'));
    expect(info, contains('android:targetCellWidth'));
    expect(info, contains('android:targetCellHeight'));
  });

  test('main Android manifest registers widget rotation receiver', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:name=".WidgetRotationReceiver"'));
    expect(
      manifest,
      contains('top.schonavi.app.action.ROTATE_PREPARATION_WIDGET'),
    );
  });

  test(
    'Android shortcuts route AI entry points to conversational home tabs',
    () {
      final shortcuts = File(
        'android/app/src/main/res/xml/shortcuts.xml',
      ).readAsStringSync();

      expect(shortcuts, contains('android:shortcutId="ai_mentor"'));
      expect(shortcuts, contains('android:value="/home?tab=mentor"'));
      expect(shortcuts, contains('android:shortcutId="ai_competition"'));
      expect(shortcuts, contains('android:value="/home?tab=competition"'));
    },
  );

  test('deprecated standalone recommendation pages stay removed', () {
    for (final path in [
      'lib/features/recommendation/pages/recommendation_page.dart',
      'lib/features/competition_recommendation/pages/competition_recommendation_page.dart',
    ]) {
      expect(
        File(path).existsSync(),
        isFalse,
        reason: '$path should not return',
      );
    }
  });
}
