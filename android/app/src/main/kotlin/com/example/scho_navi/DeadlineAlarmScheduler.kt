package top.schonavi.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.LocalDate
import java.time.ZonedDateTime

object DeadlineAlarmScheduler {
    fun groupAlertsByDay(alerts: List<DeadlineAlert>): Map<String, List<DeadlineAlert>> {
        return alerts.groupBy { it.alertIsoDay }.toSortedMap()
    }

    fun filterFutureDays(days: Collection<String>, now: ZonedDateTime): List<String> {
        return days.filter { day ->
            val target = runCatching {
                LocalDate.parse(day).atTime(9, 0).atZone(now.zone).toInstant()
            }.getOrNull()
            target != null && target.isAfter(now.toInstant())
        }
    }

    fun apply(context: Context, alerts: List<DeadlineAlert>) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val now = ZonedDateTime.now()
        val grouped = groupAlertsByDay(alerts)
        val futureDays = filterFutureDays(grouped.keys, now)

        val oldEntries = ReminderAlarmRegistry.loadDeadline(context)
        for (entry in oldEntries) {
            if (entry.isoDay !in futureDays) {
                alarmManager.cancel(deadlinePendingIntent(context, entry.isoDay))
            }
        }

        val newEntries = futureDays.map { AlarmRegistryEntry(it, "schonavi://alarm/deadline/$it") }
        for (isoDay in futureDays) {
            val target = LocalDate.parse(isoDay).atTime(9, 0).atZone(now.zone).toInstant().toEpochMilli()
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                target,
                deadlinePendingIntent(context, isoDay),
            )
        }

        ReminderAlarmRegistry.save(
            context,
            deadline = newEntries,
            snooze = ReminderAlarmRegistry.loadSnooze(context),
        )
    }

    private fun deadlinePendingIntent(context: Context, isoDay: String): PendingIntent {
        val intent = Intent(context, DeadlineAlarmReceiver::class.java).apply {
            action = "top.schonavi.app.action.DEADLINE_ALARM"
            data = Uri.parse("schonavi://alarm/deadline/$isoDay")
            putExtra("alertIsoDay", isoDay)
        }
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

class DeadlineAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val alertIsoDay = intent.getStringExtra("alertIsoDay") ?: return
        val snapshot = ReminderStorage.loadSnapshot(context)
        if (snapshot.schemaVersion !in 1..3) return
        if (!ReminderNotificationFactory.canNotify(context)) return
        ReminderNotificationFactory.ensureChannels(context)
        val manager = context.getSystemService(android.app.NotificationManager::class.java)

        val dayAlerts = snapshot.deadlineAlerts.filter { it.alertIsoDay == alertIsoDay }
        if (dayAlerts.isEmpty()) return

        for (alert in dayAlerts) {
            val viewIntent = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).apply {
                    action = "top.schonavi.app.OPEN_DEADLINE_${alert.planId}"
                    putExtra(MainActivity.EXTRA_ROUTE, "/preparation-plans/${Uri.encode(alert.planId)}")
                    flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = ReminderNotificationFactory.buildDeadlineChild(context, alert, viewIntent)
            manager.notify(
                ReminderNotificationFactory.deadlineTag(alert.planId, alert.daysBefore),
                ReminderNotificationFactory.DEADLINE_NOTIFICATION_ID,
                notification,
            )
        }

        if (dayAlerts.size >= 2) {
            val summary = ReminderNotificationFactory.buildDeadlineSummary(context, alertIsoDay, dayAlerts.size)
            manager.notify("summary:deadlines:$alertIsoDay", ReminderNotificationFactory.DEADLINE_SUMMARY_ID, summary)
        }
    }
}
