import '../../core/storage/local_store.dart';
import '../../domain/entities/preparation_plan.dart';
import '../../domain/entities/preparation_reminder.dart';

class PreparationReminderStore {
  PreparationReminderStore(this._store);

  static const preferencesKey = 'preparation_reminder_preferences.v1';
  static const activityDaysKey = 'preparation_activity_days.v1';

  final LocalStore _store;

  ReminderPreferences loadPreferences() {
    final json = _store.getJson(preferencesKey);
    return json == null
        ? const ReminderPreferences()
        : ReminderPreferences.fromJson(json);
  }

  Future<void> savePreferences(ReminderPreferences preferences) =>
      _store.setJson(preferencesKey, preferences.toJson());

  Set<String> loadActivityDays() => (_store.getJsonList(activityDaysKey) ?? [])
      .whereType<String>()
      .where(_isIsoDay)
      .toSet();

  Future<Set<String>> reconcileActivityDays(List<PreparationPlan> plans) async {
    final days = loadActivityDays();
    for (final plan in plans) {
      for (final phase in plan.phases) {
        for (final task in phase.tasks) {
          final completedAt = task.completedAt;
          if (completedAt != null) days.add(_isoDay(completedAt));
        }
      }
    }
    final sorted = days.toList()..sort();
    await _store.setJsonList(activityDaysKey, sorted);
    return days;
  }

  Future<void> clearAll() async {
    await _store.remove(preferencesKey);
    await _store.remove(activityDaysKey);
  }

  bool _isIsoDay(String value) =>
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value);

  String _isoDay(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
