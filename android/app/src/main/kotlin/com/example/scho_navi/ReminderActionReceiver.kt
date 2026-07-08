package top.schonavi.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri

class ReminderActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val planId = intent.getStringExtra("planId") ?: return
        val taskId = intent.getStringExtra("taskId") ?: return
        val pendingResult = goAsync()

        when {
            action.endsWith("COMPLETE") -> {
                NotificationActionCoordinator.complete(context, planId, taskId,
                    onSuccess = {
                        cancelTaskNotification(context, planId, taskId)
                        pendingResult.finish()
                    },
                    onFailure = { pendingResult.finish() },
                )
            }
            action.endsWith("SNOOZE") -> {
                scheduleSnooze(context, planId, taskId)
                cancelTaskNotification(context, planId, taskId)
                pendingResult.finish()
            }
        }
    }

    private fun scheduleSnooze(context: Context, planId: String, taskId: String) {
        val triggerAt = System.currentTimeMillis() + 60 * 60 * 1000
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAt,
            snoozePendingIntent(context, planId, taskId),
        )
        val snoozes = ReminderAlarmRegistry.loadSnooze(context)
            .filterNot { it.planId == planId && it.taskId == taskId } +
            SnoozeRegistryEntry(planId, taskId, triggerAt, "schonavi://alarm/snooze/${Uri.encode(planId)}/${Uri.encode(taskId)}")
        ReminderAlarmRegistry.save(context,
            deadline = ReminderAlarmRegistry.loadDeadline(context),
            snooze = snoozes,
        )
    }

    private fun cancelTaskNotification(context: Context, planId: String, taskId: String) {
        context.getSystemService(android.app.NotificationManager::class.java)
            .cancel(ReminderNotificationFactory.taskTag(planId, taskId),
                ReminderNotificationFactory.TASK_NOTIFICATION_ID)
    }

    companion object {
        fun snoozePendingIntent(context: Context, planId: String, taskId: String): PendingIntent {
            val encodedPlan = Uri.encode(planId)
            val encodedTask = Uri.encode(taskId)
            val intent = Intent(context, SnoozedTaskReceiver::class.java).apply {
                action = "top.schonavi.app.action.SNOOZE_FIRE"
                data = Uri.parse("schonavi://alarm/snooze/$encodedPlan/$encodedTask")
                putExtra("planId", planId)
                putExtra("taskId", taskId)
            }
            return PendingIntent.getBroadcast(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}

class SnoozedTaskReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val planId = intent.getStringExtra("planId") ?: return
        val taskId = intent.getStringExtra("taskId") ?: return
        val snapshot = ReminderStorage.loadSnapshot(context)
        if (snapshot.schemaVersion !in 1..3) return
        val plan = snapshot.plans.firstOrNull { it.planId == planId } ?: return
        val task = plan.pendingTasks.firstOrNull { it.taskId == taskId } ?: return
        ReminderNotificationFactory.ensureChannels(context)
        val completeIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, ReminderActionReceiver::class.java).apply {
                action = "top.schonavi.app.action.NOTIFICATION_COMPLETE"
                data = Uri.parse("schonavi://notification/action/COMPLETE/${Uri.encode(planId)}/${Uri.encode(taskId)}")
                putExtra("planId", planId)
                putExtra("taskId", taskId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val snoozeIntent = PendingIntent.getBroadcast(
            context, 0,
            Intent(context, ReminderActionReceiver::class.java).apply {
                action = "top.schonavi.app.action.NOTIFICATION_SNOOZE"
                data = Uri.parse("schonavi://notification/action/SNOOZE/${Uri.encode(planId)}/${Uri.encode(taskId)}")
                putExtra("planId", planId)
                putExtra("taskId", taskId)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val viewIntent = PendingIntent.getActivity(
            context, 4105,
            Intent(context, MainActivity::class.java).apply {
                action = "top.schonavi.app.OPEN_REMINDER_$planId"
                putExtra(MainActivity.EXTRA_ROUTE, "/preparation-plans/${Uri.encode(planId)}")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = ReminderNotificationFactory.buildTaskNotification(
            context, plan, task, completeIntent, snoozeIntent, viewIntent
        )
        context.getSystemService(android.app.NotificationManager::class.java)
            .notify(ReminderNotificationFactory.taskTag(planId, taskId),
                ReminderNotificationFactory.TASK_NOTIFICATION_ID, notification)
        val snoozes = ReminderAlarmRegistry.loadSnooze(context)
            .filterNot { it.planId == planId && it.taskId == taskId }
        ReminderAlarmRegistry.save(context,
            deadline = ReminderAlarmRegistry.loadDeadline(context),
            snooze = snoozes,
        )
    }
}
