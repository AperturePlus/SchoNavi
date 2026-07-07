package top.schonavi.app

import android.content.Context
import org.json.JSONObject

data class ReminderPhase(
    val title: String,
    val startDate: String,
    val endDate: String,
    val status: String,
)

data class ReminderTask(
    val taskId: String,
    val title: String,
    val dueIsoDay: String,
    val sortOrder: Int,
)

data class ReminderPlan(
    val planId: String,
    val competitionName: String,
    val targetDate: String,
    val currentPhase: String,
    val completedTasks: Int,
    val totalTasks: Int,
    val nextTaskTitle: String?,
    val nextTaskDueDate: String?,
    val phases: List<ReminderPhase> = emptyList(),
    val pendingTasks: List<ReminderTask> = emptyList(),
)

data class DeadlineAlert(
    val planId: String,
    val competitionName: String,
    val alertIsoDay: String,
    val daysBefore: Int,
    val deadlineIsoDay: String,
)

data class ReminderSnapshot(
    val currentStreak: Int,
    val lastActivityDay: String?,
    val plans: List<ReminderPlan>,
    val deadlineAlerts: List<DeadlineAlert> = emptyList(),
    val schemaVersion: Int = 0,
)

data class ReminderSchedule(val enabled: Boolean, val hour: Int, val minute: Int)

data class AlarmRegistryEntry(val isoDay: String, val dataUri: String)

data class SnoozeRegistryEntry(
    val planId: String,
    val taskId: String,
    val triggerAtEpochMs: Long,
    val dataUri: String,
)

object ReminderStorage {
    private const val PREFS = "scho_navi_preparation_reminders"
    private const val SNAPSHOT = "snapshot_json"
    private const val ENABLED = "notification_enabled"
    private const val HOUR = "notification_hour"
    private const val MINUTE = "notification_minute"

    fun saveSnapshot(context: Context, json: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(SNAPSHOT, json)
            .apply()
    }

    fun loadSnapshot(context: Context): ReminderSnapshot {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(SNAPSHOT, null) ?: return ReminderSnapshot(0, null, emptyList())
        return parseSnapshotJson(raw)
    }

    fun parseSnapshotJson(raw: String): ReminderSnapshot {
        return try {
            val root = JSONObject(raw)
            val schema = root.optInt("schemaVersion", 0)
            if (schema !in 1..3) return ReminderSnapshot(0, null, emptyList())
            val plansJson = root.optJSONArray("plans")
            val plans = buildList {
                if (plansJson != null) {
                    for (index in 0 until plansJson.length()) {
                        val item = plansJson.optJSONObject(index) ?: continue
                        val phasesJson = item.optJSONArray("phases")
                        val phases = buildList {
                            if (phasesJson != null) {
                                for (pi in 0 until phasesJson.length()) {
                                    val ph = phasesJson.optJSONObject(pi) ?: continue
                                    add(
                                        ReminderPhase(
                                            title = ph.optString("title"),
                                            startDate = ph.optString("startDate"),
                                            endDate = ph.optString("endDate"),
                                            status = ph.optString("status", "upcoming"),
                                        ),
                                    )
                                }
                            }
                        }
                        val pendingJson = item.optJSONArray("pendingTasks")
                        val pending = buildList {
                            if (pendingJson != null) {
                                for (ti in 0 until pendingJson.length()) {
                                    val t = pendingJson.optJSONObject(ti) ?: continue
                                    add(
                                        ReminderTask(
                                            taskId = t.optString("taskId"),
                                            title = t.optString("title"),
                                            dueIsoDay = t.optString("dueIsoDay"),
                                            sortOrder = t.optInt("sortOrder"),
                                        ),
                                    )
                                }
                            }
                        }
                        add(
                            ReminderPlan(
                                planId = item.optString("planId"),
                                competitionName = item.optString("competitionName"),
                                targetDate = item.optString("targetDate"),
                                currentPhase = item.optString("currentPhase"),
                                completedTasks = item.optInt("completedTasks"),
                                totalTasks = item.optInt("totalTasks"),
                                nextTaskTitle = item.optString("nextTaskTitle").ifBlank { null },
                                nextTaskDueDate = item.optString("nextTaskDueDate").ifBlank { null },
                                phases = phases,
                                pendingTasks = pending,
                            ),
                        )
                    }
                }
            }
            val alertsJson = root.optJSONArray("deadlineAlerts")
            val alerts = buildList {
                if (alertsJson != null) {
                    for (ai in 0 until alertsJson.length()) {
                        val a = alertsJson.optJSONObject(ai) ?: continue
                        add(
                            DeadlineAlert(
                                planId = a.optString("planId"),
                                competitionName = a.optString("competitionName"),
                                alertIsoDay = a.optString("alertIsoDay"),
                                daysBefore = a.optInt("daysBefore"),
                                deadlineIsoDay = a.optString("deadlineIsoDay"),
                            ),
                        )
                    }
                }
            }
            ReminderSnapshot(
                currentStreak = root.optInt("currentStreak"),
                lastActivityDay = root.optString("lastActivityDay").ifBlank { null },
                plans = plans,
                deadlineAlerts = alerts,
                schemaVersion = schema,
            )
        } catch (_: Exception) {
            ReminderSnapshot(0, null, emptyList())
        }
    }

    fun saveSchedule(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(ENABLED, enabled)
            .putInt(HOUR, hour.coerceIn(0, 23))
            .putInt(MINUTE, minute.coerceIn(0, 59))
            .apply()
    }

    fun loadSchedule(context: Context): ReminderSchedule {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return ReminderSchedule(
            enabled = prefs.getBoolean(ENABLED, false),
            hour = prefs.getInt(HOUR, 20),
            minute = prefs.getInt(MINUTE, 0),
        )
    }

    fun widgetIndex(context: Context, appWidgetId: Int): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt("widget_index_$appWidgetId", -1)

    fun saveWidgetIndex(context: Context, appWidgetId: Int, index: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt("widget_index_$appWidgetId", index)
            .apply()
    }

    fun deleteWidgetIndex(context: Context, appWidgetId: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove("widget_index_$appWidgetId")
            .apply()
    }
}

object ReminderAlarmRegistry {
    private const val KEY = "alarm_registry"
    private const val DEADLINE = "deadline_entries"
    private const val SNOOZE = "snooze_entries"

    fun loadDeadline(context: Context): List<AlarmRegistryEntry> =
        loadList(context, DEADLINE, ::parseDeadline)

    fun loadSnooze(context: Context): List<SnoozeRegistryEntry> =
        loadList(context, SNOOZE, ::parseSnooze)

    fun save(context: Context, deadline: List<AlarmRegistryEntry>, snooze: List<SnoozeRegistryEntry>) {
        val prefs = context.getSharedPreferences(KEY, Context.MODE_PRIVATE).edit()
        prefs.putString(DEADLINE, deadline.joinToString("|") { "${it.isoDay}\t${it.dataUri}" })
        prefs.putString(SNOOZE, snooze.joinToString("|") { "${it.planId}\t${it.taskId}\t${it.triggerAtEpochMs}\t${it.dataUri}" })
        prefs.apply()
    }

    fun clearAll(context: Context) {
        context.getSharedPreferences(KEY, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun parseDeadline(s: String): AlarmRegistryEntry? {
        val parts = s.split("\t")
        if (parts.size != 2) return null
        return AlarmRegistryEntry(parts[0], parts[1])
    }

    private fun parseSnooze(s: String): SnoozeRegistryEntry? {
        val parts = s.split("\t")
        if (parts.size != 4) return null
        return SnoozeRegistryEntry(parts[0], parts[1], parts[2].toLongOrNull() ?: return null, parts[3])
    }

    private fun <T> loadList(context: Context, key: String, parse: (String) -> T?): List<T> {
        val raw = context.getSharedPreferences(KEY, Context.MODE_PRIVATE).getString(key, null) ?: return emptyList()
        return raw.split("|").mapNotNull(parse)
    }
}
