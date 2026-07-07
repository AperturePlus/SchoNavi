package top.schonavi.app

import android.Manifest
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Build
import android.provider.CalendarContract
import android.provider.Settings
import android.view.animation.DecelerateInterpolator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val EXTRA_ROUTE = "route"
        private const val CHANNEL_NAME = "top.schonavi.app/preparation_reminders"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4106
        private const val CALENDAR_PERMISSION_REQUEST = 4107
    }

    private var remindersChannel: MethodChannel? = null
    private var pendingInitialRoute: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarEvent: CalendarEventParams? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingInitialRoute = intent?.getStringExtra(EXTRA_ROUTE)
        super.onCreate(savedInstanceState)
        WidgetRotationScheduler.apply(this)
        ReminderNotificationFactory.ensureChannels(this)
        val snapshot = ReminderStorage.loadSnapshot(this)
        DeadlineAlarmScheduler.apply(this, snapshot.deadlineAlerts)
        ReminderScheduler.apply(this)

        splashScreen.setOnExitAnimationListener { splashScreenView ->
            splashScreenView.animate()
                .alpha(0f)
                .setDuration(120L)
                .setInterpolator(DecelerateInterpolator())
                .withEndAction { splashScreenView.remove() }
                .start()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        remindersChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        remindersChannel?.setMethodCallHandler(::handleReminderCall)
        NotificationActionCoordinator.registerUiChannel(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        NotificationActionCoordinator.unregisterUiChannel()
        remindersChannel?.setMethodCallHandler(null)
        remindersChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val route = intent.getStringExtra(EXTRA_ROUTE) ?: return
        pendingInitialRoute = route
        remindersChannel?.invokeMethod("openRoute", route)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALENDAR_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            val pending = pendingCalendarPermissionResult
            val event = pendingCalendarEvent
            pendingCalendarPermissionResult = null
            pendingCalendarEvent = null
            if (pending == null || event == null) return
            if (granted) {
                writeToCalendarOrFallback(event, pending)
            } else {
                // 拒绝 → 不再直接写入，走 fallback intent
                val startMs = CalendarEventParams.startUtcMs(event.isoDay)
                val endMs = startMs + 24L * 60 * 60 * 1000
                launchInsertIntent(event, startMs, endMs, pending)
            }
            return
        }
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        pendingPermissionResult?.success(notificationStatus())
        pendingPermissionResult = null
    }

    private fun handleReminderCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "syncSnapshot" -> {
                    val json = call.arguments as? String ?: "{}"
                    ReminderStorage.saveSnapshot(this, json)
                    PreparationWidgetProvider.refreshAll(this)
                    WidgetRotationScheduler.apply(this)
                    val snapshot = ReminderStorage.loadSnapshot(this)
                    DeadlineAlarmScheduler.apply(this, snapshot.deadlineAlerts)
                    result.success(null)
                }
                "updateSchedule" -> {
                    val args = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                    ReminderStorage.saveSchedule(
                        this,
                        enabled = args["enabled"] as? Boolean ?: false,
                        hour = (args["hour"] as? Number)?.toInt() ?: 20,
                        minute = (args["minute"] as? Number)?.toInt() ?: 0,
                    )
                    ReminderScheduler.apply(this)
                    result.success(null)
                }
                "getNotificationStatus" -> result.success(notificationStatus())
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "pinWidget" -> result.success(pinWidget())
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(null)
                }
                "addDeadlineEvent" -> {
                    val json = call.arguments as? Map<*, *> ?: emptyMap<Any?, Any?>()
                    val params = CalendarEventParams.fromArgs(json)
                    if (params == null) {
                        result.error("bad_args", "missing title/isoDay", null)
                        return
                    }
                    addDeadlineEvent(params, result)
                }
                "takeInitialRoute" -> result.success(takeInitialRoute())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("preparation_reminders_error", error.message, null)
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(notificationStatus())
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(notificationStatus())
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_request_in_progress", "Notification permission request is already in progress.", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun notificationStatus(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return "denied"
        }
        if (!getSystemService(NotificationManager::class.java).areNotificationsEnabled()) {
            return "denied"
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) "granted" else "notRequired"
    }

    private fun pinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(AppWidgetManager::class.java)
        if (!manager.isRequestPinAppWidgetSupported) return false
        val provider = ComponentName(this, PreparationWidgetProvider::class.java)
        manager.requestPinAppWidget(provider, null, null)
        return true
    }

    private data class CalendarEventParams(
        val title: String,
        val isoDay: String,
        val location: String?,
        val notes: String?,
    ) {
        companion object {
            fun fromArgs(args: Map<*, *>): CalendarEventParams? {
                val title = args["title"] as? String
                val isoDay = args["isoDay"] as? String
                if (title == null || isoDay == null) return null
                return CalendarEventParams(
                    title = title,
                    isoDay = isoDay,
                    location = args["location"] as? String,
                    notes = args["notes"] as? String,
                )
            }

            /** ISO 日按 UTC 日历日转全天事件边界（避免非 UTC 时区漂移）。 */
            fun startUtcMs(isoDay: String): Long {
                val (y, m, d) = isoDay.split("-").map { it.toInt() }
                val cal = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC"))
                cal.clear()
                cal.set(y, m - 1, d, 0, 0, 0)
                return cal.timeInMillis
            }
        }
    }

    private fun addDeadlineEvent(params: CalendarEventParams, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // 低于 23 无运行时权限，直接尝试写入。
            writeToCalendarOrFallback(params, result)
            return
        }
        val granted = checkSelfPermission(Manifest.permission.WRITE_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            writeToCalendarOrFallback(params, result)
            return
        }
        if (pendingCalendarPermissionResult != null) {
            result.error("permission_request_in_progress", "Calendar permission request is already in progress.", null)
            return
        }
        pendingCalendarPermissionResult = result
        pendingCalendarEvent = params
        requestPermissions(
            arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
            CALENDAR_PERMISSION_REQUEST,
        )
    }

    private fun writeToCalendarOrFallback(
        params: CalendarEventParams,
        result: MethodChannel.Result,
    ) {
        val startMs = CalendarEventParams.startUtcMs(params.isoDay)
        val endMs = startMs + 24L * 60 * 60 * 1000
        try {
            val calId = firstWritableCalendarId()
            if (calId != null) {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.TITLE, params.title)
                    put(CalendarContract.Events.DTSTART, startMs)
                    put(CalendarContract.Events.DTEND, endMs)
                    put(CalendarContract.Events.ALL_DAY, 1)
                    put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
                    put(CalendarContract.Events.CALENDAR_ID, calId)
                    if (params.notes != null) put(CalendarContract.Events.DESCRIPTION, params.notes)
                    if (params.location != null) put(CalendarContract.Events.EVENT_LOCATION, params.location)
                }
                val uri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
                if (uri != null) {
                    result.success("success")
                    return
                }
            }
        } catch (_: Exception) {
            // 落入 fallback
        }
        launchInsertIntent(params, startMs, endMs, result)
    }

    private fun firstWritableCalendarId(): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL,
        )
        val sel = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL} >= ${CalendarContract.Calendars.CAL_ACCESS_OWNER}"
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            sel,
            null,
            null,
        )?.use { c ->
            if (c.moveToFirst()) return c.getLong(0)
        }
        return null
    }

    private fun launchInsertIntent(
        params: CalendarEventParams,
        startMs: Long,
        endMs: Long,
        result: MethodChannel.Result,
    ) {
        val intent = Intent(Intent.ACTION_INSERT)
            .setData(CalendarContract.Events.CONTENT_URI)
            .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startMs)
            .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endMs)
            .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, true)
            .putExtra(CalendarContract.Events.TITLE, params.title)
        if (params.location != null) intent.putExtra(CalendarContract.Events.EVENT_LOCATION, params.location)
        if (params.notes != null) intent.putExtra(CalendarContract.Events.DESCRIPTION, params.notes)
        try {
            startActivity(intent)
            result.success("fallback")
        } catch (_: ActivityNotFoundException) {
            result.success("failed")
        }
    }

    private fun openNotificationSettings() {
        startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName),
        )
    }

    private fun takeInitialRoute(): String? {
        val route = pendingInitialRoute ?: intent?.getStringExtra(EXTRA_ROUTE)
        pendingInitialRoute = null
        intent?.removeExtra(EXTRA_ROUTE)
        return route
    }
}
