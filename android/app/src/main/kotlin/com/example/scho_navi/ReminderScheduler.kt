package top.schonavi.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.time.ZonedDateTime

data class Digest(
    val remainingToday: Int,
    val upcomingDeadlines: Int,
    val nearestDeadlineName: String?,
    val nearestDeadlineDay: String?,
)

object ReminderDigest {
    fun project(snapshot: ReminderSnapshot, today: java.time.LocalDate): Digest {
        val todayStr = today.toString()
        var remaining = 0
        var upcoming = 0
        var nearest: ReminderPlan? = null
        for (plan in snapshot.plans) {
            remaining += plan.pendingTasks.count { it.dueIsoDay == todayStr }
            val target = runCatching { java.time.LocalDate.parse(plan.targetDate) }.getOrNull()
            if (target != null && !target.isBefore(today)) {
                if (target.isBefore(today.plusDays(31))) upcoming++
                val nearestTarget = nearest?.let {
                    runCatching { java.time.LocalDate.parse(it.targetDate) }.getOrNull()
                }
                if (nearest == null || (nearestTarget != null && target.isBefore(nearestTarget))) {
                    nearest = plan
                }
            }
        }
        return Digest(
            remainingToday = remaining,
            upcomingDeadlines = upcoming,
            nearestDeadlineName = nearest?.competitionName,
            nearestDeadlineDay = nearest?.targetDate,
        )
    }
}

object ReminderScheduler {
    const val ACTION_NOTIFY = "top.schonavi.app.action.SEND_PREPARATION_REMINDER"

    fun apply(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = pendingIntent(context)
        alarmManager.cancel(pendingIntent)
        val schedule = ReminderStorage.loadSchedule(context)
        if (!schedule.enabled) return

        val now = ZonedDateTime.now()
        var next = now.toLocalDate().atTime(schedule.hour, schedule.minute).atZone(now.zone)
        if (!next.isAfter(now)) next = next.plusDays(1)
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            next.toInstant().toEpochMilli(),
            pendingIntent,
        )
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, DailyReminderReceiver::class.java).apply {
            action = ACTION_NOTIFY
            data = Uri.parse("schonavi://alarm/daily")
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.apply(context)
        val schedule = ReminderStorage.loadSchedule(context)
        if (!schedule.enabled || !ReminderNotificationFactory.canNotify(context)) return
        val snapshot = ReminderStorage.loadSnapshot(context)
        if (snapshot.schemaVersion !in 1..3) return
        ReminderNotificationFactory.ensureChannels(context)

        val today = java.time.LocalDate.now()
        val candidate = snapshot.plans
            .filter { it.pendingTasks.isNotEmpty() }
            .minWithOrNull(
                compareBy<ReminderPlan> { it.pendingTasks.first().dueIsoDay }
                    .thenBy { it.pendingTasks.first().sortOrder }
                    .thenBy { it.targetDate }
                    .thenBy { it.planId },
            )

        if (candidate != null) {
            val task = candidate.pendingTasks.first()
            val completeIntent = actionPendingIntent(context, "COMPLETE", candidate.planId, task.taskId)
            val snoozeIntent = actionPendingIntent(context, "SNOOZE", candidate.planId, task.taskId)
            val viewIntent = viewPendingIntent(context, candidate.planId)
            val notification = ReminderNotificationFactory.buildTaskNotification(
                context, candidate, task, completeIntent, snoozeIntent, viewIntent,
            )
            context.getSystemService(NotificationManager::class.java)
                .notify(
                    ReminderNotificationFactory.taskTag(candidate.planId, task.taskId),
                    ReminderNotificationFactory.TASK_NOTIFICATION_ID,
                    notification,
                )
        }

        val digest = ReminderDigest.project(snapshot, today)
        val summary = ReminderNotificationFactory.buildPreparationSummary(
            context,
            digest.remainingToday,
            digest.upcomingDeadlines,
            digest.nearestDeadlineName,
            digest.nearestDeadlineDay,
        )
        context.getSystemService(NotificationManager::class.java)
            .notify("summary:preparation", ReminderNotificationFactory.PREPARATION_SUMMARY_ID, summary)
    }

    private fun actionPendingIntent(context: Context, action: String, planId: String, taskId: String): PendingIntent {
        val encodedPlan = Uri.encode(planId)
        val encodedTask = Uri.encode(taskId)
        val data = Uri.parse("schonavi://notification/action/$action/$encodedPlan/$encodedTask")
        val intent = Intent(context, ReminderActionReceiver::class.java).apply {
            this.action = "top.schonavi.app.action.NOTIFICATION_$action"
            setDataAndNormalize(data)
            putExtra("planId", planId)
            putExtra("taskId", taskId)
        }
        return PendingIntent.getBroadcast(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun viewPendingIntent(context: Context, planId: String): PendingIntent {
        val route = "/preparation-plans/${Uri.encode(planId)}"
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "top.schonavi.app.OPEN_REMINDER_$planId"
            putExtra(MainActivity.EXTRA_ROUTE, route)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context, 4105, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.apply(context)
        val snapshot = ReminderStorage.loadSnapshot(context)
        DeadlineAlarmScheduler.apply(context, snapshot.deadlineAlerts)
        val now = System.currentTimeMillis()
        val snoozes = ReminderAlarmRegistry.loadSnooze(context).filter { it.triggerAtEpochMs > now }
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        for (s in snoozes) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                s.triggerAtEpochMs,
                ReminderActionReceiver.snoozePendingIntent(context, s.planId, s.taskId),
            )
        }
        PreparationWidgetProvider.refreshAll(context)
    }
}
