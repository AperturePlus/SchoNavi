package top.schonavi.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object WidgetRotationScheduler {
    private const val REQUEST_CODE = 4107
    private const val INTERVAL_MS = 30_000L

    fun apply(context: Context) {
        val snapshot = ReminderStorage.loadSnapshot(context)
        val shouldRun = snapshot.plans.size > 1
        if (shouldRun) start(context) else stop(context)
    }

    fun start(context: Context) {
        val alarmManager = context.getSystemService(AlarmManager::class.java)
        val pendingIntent = pendingIntent(context)
        alarmManager.cancel(pendingIntent)
        alarmManager.setRepeating(
            AlarmManager.RTC,
            System.currentTimeMillis() + INTERVAL_MS,
            INTERVAL_MS,
            pendingIntent,
        )
    }

    fun stop(context: Context) {
        context.getSystemService(AlarmManager::class.java)
            .cancel(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, WidgetRotationReceiver::class.java).apply {
            action = PreparationWidgetProvider.ACTION_ROTATE
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

class WidgetRotationReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != PreparationWidgetProvider.ACTION_ROTATE) return
        // 转发给 PreparationWidgetProvider，复用其 onReceive(ACTION_ROTATE) 做 rotate=true 渲染。
        context.sendBroadcast(
            Intent(context, PreparationWidgetProvider::class.java).apply {
                action = PreparationWidgetProvider.ACTION_ROTATE
            },
        )
    }
}
