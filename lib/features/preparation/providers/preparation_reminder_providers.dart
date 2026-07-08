import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/platform/preparation_reminder_platform.dart';
import '../../../data/local/preparation_reminder_store.dart';
import '../../../domain/entities/preparation_plan.dart';
import '../../../domain/entities/preparation_reminder.dart';
import '../../../domain/services/preparation_reminder_builder.dart';
import '../services/complete_notification_task_use_case.dart';
import 'preparation_providers.dart';

const MethodChannel notificationActionChannel = MethodChannel(
  'top.schonavi.app/notification_actions',
);

typedef NotificationActionHandler = Future<dynamic> Function(MethodCall call);

NotificationActionHandler buildNotificationActionHandler(
  CompleteNotificationTaskUseCase useCase,
) {
  return (MethodCall call) async {
    if (call.method != 'completeNotificationTask') {
      throw PlatformException(
        code: 'unimplemented',
        message: 'unknown method ${call.method}',
      );
    }
    final args = (call.arguments as Map?) ?? const <String, dynamic>{};
    final planId = args['planId'] as String?;
    final taskId = args['taskId'] as String?;
    if (planId == null || taskId == null) {
      throw PlatformException(
        code: 'invalid_arguments',
        message: 'planId/taskId required',
      );
    }
    final outcome = await useCase.call(planId: planId, taskId: taskId);
    switch (outcome.result) {
      case CompleteTaskResult.completed:
        return {
          'status': 'completed',
          'snapshotJson': jsonEncode(outcome.snapshot!.toJson()),
        };
      case CompleteTaskResult.alreadyCompleted:
        return {
          'status': 'already_completed',
          'snapshotJson': jsonEncode(outcome.snapshot!.toJson()),
        };
      case CompleteTaskResult.notFound:
        throw PlatformException(
          code: 'not_found',
          message: 'plan or task not found',
        );
      case CompleteTaskResult.conflict:
        throw PlatformException(
          code: 'conflict',
          message: 'CAS retry exhausted',
        );
      case CompleteTaskResult.persistenceFailed:
        throw PlatformException(
          code: 'persistence_failed',
          message: 'save failed',
        );
    }
  };
}

final preparationReminderPlatformProvider =
    Provider<PreparationReminderPlatform>(
      (_) => MethodChannelPreparationReminderPlatform(),
    );

final preparationReminderStoreProvider = Provider<PreparationReminderStore>(
  (ref) => PreparationReminderStore(ref.watch(localStoreProvider)),
);

final reminderPreferencesProvider =
    NotifierProvider<ReminderPreferencesNotifier, ReminderPreferences>(
      ReminderPreferencesNotifier.new,
    );

class ReminderPreferencesNotifier extends Notifier<ReminderPreferences> {
  PreparationReminderStore get _store =>
      ref.read(preparationReminderStoreProvider);

  @override
  ReminderPreferences build() => _store.loadPreferences();

  Future<void> setEnabled(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    await _store.savePreferences(state);
    await ref.read(preparationReminderPlatformProvider).updateSchedule(state);
  }

  Future<void> setTime({required int hour, required int minute}) async {
    state = state.copyWith(hour: hour, minute: minute);
    await _store.savePreferences(state);
    await ref.read(preparationReminderPlatformProvider).updateSchedule(state);
  }
}

final preparationReminderSyncProvider = Provider<void>((ref) {
  final repository = ref.watch(preparationPlanRepositoryProvider);
  final store = ref.watch(preparationReminderStoreProvider);
  final platform = ref.watch(preparationReminderPlatformProvider);
  const builder = PreparationReminderBuilder();
  Future<void> guard = Future<void>.value();

  Future<void> sync(List<PreparationPlan> plans) {
    guard = guard
        .then((_) async {
          final days = await store.reconcileActivityDays(plans);
          final snapshot = builder.build(
            plans: plans,
            activityDays: days,
            now: DateTime.now(),
          );
          await platform.syncSnapshot(snapshot);
        })
        .catchError((_) {});
    return guard;
  }

  final subscription = repository.watch().listen(sync);
  ref.onDispose(subscription.cancel);

  final actionUseCase = CompleteNotificationTaskUseCase(
    repository: repository,
    builder: builder,
    activityDays: store.loadActivityDays(),
    now: DateTime.now,
  );
  notificationActionChannel.setMethodCallHandler(
    buildNotificationActionHandler(actionUseCase),
  );
  ref.onDispose(() {
    notificationActionChannel.setMethodCallHandler(null);
  });

  ref.listen<ReminderPreferences>(reminderPreferencesProvider, (_, next) {
    unawaited(platform.updateSchedule(next));
  });
  unawaited(platform.updateSchedule(ref.read(reminderPreferencesProvider)));
});
