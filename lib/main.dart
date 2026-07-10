import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bootstrap/app_bootstrap.dart';
import 'core/config/app_config.dart';
import 'core/storage/shared_preferences_local_store.dart';
import 'data/local/local_preparation_plan_repository.dart';
import 'data/local/preparation_reminder_store.dart';
import 'domain/services/preparation_reminder_builder.dart';
import 'features/preparation/providers/preparation_reminder_providers.dart';
import 'features/preparation/services/complete_notification_task_use_case.dart';

const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _showApiErrorDetails = bool.fromEnvironment('API_SHOW_ERROR_DETAILS');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AppBootstrap(
      initialAppConfig: AppConfig.resolve(
        apiBaseUrl: _apiBaseUrl,
        showApiErrorDetails: _showApiErrorDetails,
      ),
    ),
  );
}

@pragma('vm:entry-point')
Future<void> notificationActionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  return SharedPreferences.getInstance().then((prefs) {
    final store = SharedPreferencesLocalStore(prefs);
    final repo = LocalPreparationPlanRepository(store);
    final reminderStore = PreparationReminderStore(store);
    final useCase = CompleteNotificationTaskUseCase(
      repository: repo,
      builder: const PreparationReminderBuilder(),
      activityDays: reminderStore.loadActivityDays(),
      now: DateTime.now,
    );
    notificationActionChannel.setMethodCallHandler(
      buildNotificationActionHandler(useCase),
    );
  });
}
