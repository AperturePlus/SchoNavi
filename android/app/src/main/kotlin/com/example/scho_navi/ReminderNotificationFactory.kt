package top.schonavi.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

object ReminderNotificationFactory {
    const val CHANNEL_PREPARATION = "preparation_tasks"
    const val CHANNEL_DEADLINES = "competition_deadlines"
    const val CHANNEL_MENTOR = "mentor_consultations"
    private const val LEGACY_CHANNEL = "preparation_reminders"

    const val GROUP_PREPARATION = "scho_navi.preparation"
    const val GROUP_DEADLINES = "scho_navi.deadlines"

    const val TASK_NOTIFICATION_ID = 4104
    const val PREPARATION_SUMMARY_ID = 4100
    const val DEADLINE_NOTIFICATION_ID = 4200
    const val DEADLINE_SUMMARY_ID = 4201

    fun taskTag(planId: String, taskId: String) = "task:$planId:$taskId"
    fun deadlineTag(planId: String, daysBefore: Int) = "deadline:$planId:$daysBefore"

    fun canNotify(context: Context): Boolean {
        if (!context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()) return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun ensureChannels(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_PREPARATION, "备赛任务", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "每日备赛任务提醒与摘要"
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_DEADLINES, "竞赛截止", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "竞赛截止前 7/3/0 天提醒"
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_MENTOR, "导师咨询", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "导师咨询相关提醒（预留）"
            }
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.deleteNotificationChannel(LEGACY_CHANNEL)
        }
    }

    fun buildTaskNotification(
        context: Context,
        plan: ReminderPlan,
        task: ReminderTask,
        completeIntent: PendingIntent,
        snoozeIntent: PendingIntent,
        viewIntent: PendingIntent,
    ): Notification {
        val body = "下一项：${task.title} · ${task.dueIsoDay}"
        return Notification.Builder(context, CHANNEL_PREPARATION)
            .setSmallIcon(R.drawable.ic_reminder_notification)
            .setContentTitle("今晚推进「${plan.competitionName}」")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(viewIntent)
            .setGroup(GROUP_PREPARATION)
            .setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
            .addAction(R.drawable.ic_reminder_notification, "完成此任务", completeIntent)
            .addAction(R.drawable.ic_reminder_notification, "稍后提醒", snoozeIntent)
            .addAction(R.drawable.ic_reminder_notification, "查看计划", viewIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .build()
    }

    fun buildPreparationSummary(
        context: Context,
        remainingToday: Int,
        upcomingDeadlines: Int,
        nearestDeadlineName: String?,
        nearestDeadlineDay: String?,
    ): Notification {
        val deadlineText = nearestDeadlineName?.let { "最近截止竞赛 $it${nearestDeadlineDay?.let { d -> " · $d" } ?: ""}" } ?: "暂无近期截止"
        val body = "今天还有 $remainingToday 个任务 · $deadlineText · 未来 30 天 $upcomingDeadlines 个截止"
        return Notification.Builder(context, CHANNEL_PREPARATION)
            .setSmallIcon(R.drawable.ic_reminder_notification)
            .setContentTitle("今日备赛摘要")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setGroup(GROUP_PREPARATION)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
    }

    fun buildDeadlineChild(
        context: Context,
        alert: DeadlineAlert,
        viewIntent: PendingIntent,
    ): Notification {
        val dayText = if (alert.daysBefore == 0) "今天截止" else "还有 ${alert.daysBefore} 天截止"
        val body = "${alert.competitionName} · $dayText（${alert.deadlineIsoDay}）"
        return Notification.Builder(context, CHANNEL_DEADLINES)
            .setSmallIcon(R.drawable.ic_reminder_notification)
            .setContentTitle("竞赛截止提醒")
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(viewIntent)
            .setGroup(GROUP_DEADLINES)
            .setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
            .addAction(R.drawable.ic_reminder_notification, "查看计划", viewIntent)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .build()
    }

    fun buildDeadlineSummary(context: Context, alertIsoDay: String, count: Int): Notification {
        val body = "$count 个竞赛截止提醒"
        return Notification.Builder(context, CHANNEL_DEADLINES)
            .setSmallIcon(R.drawable.ic_reminder_notification)
            .setContentTitle("竞赛截止")
            .setContentText(body)
            .setGroup(GROUP_DEADLINES)
            .setGroupSummary(true)
            .setAutoCancel(true)
            .build()
    }
}
