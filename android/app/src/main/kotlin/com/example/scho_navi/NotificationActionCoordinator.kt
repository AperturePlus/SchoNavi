package top.schonavi.app

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

object NotificationActionCoordinator {
    private const val CACHE_ID = "notification_action_engine"
    private const val CHANNEL = "top.schonavi.app/notification_actions"
    private const val TIMEOUT_MS = 8000L
    private val inFlight = mutableSetOf<String>() // planId|taskId

    private var uiChannel: MethodChannel? = null

    fun registerUiChannel(engine: io.flutter.embedding.engine.FlutterEngine) {
        uiChannel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    }

    fun unregisterUiChannel() {
        uiChannel = null
    }

    fun complete(
        context: Context,
        planId: String,
        taskId: String,
        onSuccess: () -> Unit,
        onFailure: () -> Unit,
    ) {
        val key = "$planId|$taskId"
        if (!inFlight.add(key)) {
            onFailure()
            return
        }

        val channel = uiChannel ?: ensureHeadlessEngine(context)
        if (channel == null) {
            inFlight.remove(key)
            onFailure()
            return
        }

        val handler = object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result is Map<*, *>) {
                    val status = result["status"] as? String
                    if (status == "completed" || status == "already_completed") {
                        val snapshotJson = result["snapshotJson"] as? String
                        if (snapshotJson != null) {
                            ReminderStorage.saveSnapshot(context, snapshotJson)
                            val snapshot = ReminderStorage.loadSnapshot(context)
                            DeadlineAlarmScheduler.apply(context, snapshot.deadlineAlerts)
                            PreparationWidgetProvider.refreshAll(context)
                        }
                        if (inFlight.remove(key)) {
                            onSuccess()
                        }
                    } else {
                        if (inFlight.remove(key)) {
                            onFailure()
                        }
                    }
                } else {
                    if (inFlight.remove(key)) {
                        onFailure()
                    }
                }
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                if (inFlight.remove(key)) {
                    onFailure()
                }
            }

            override fun notImplemented() {
                if (inFlight.remove(key)) {
                    onFailure()
                }
            }
        }

        channel.invokeMethod(
            "completeNotificationTask",
            mapOf("planId" to planId, "taskId" to taskId),
            handler,
        )

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (inFlight.remove(key)) {
                onFailure()
                FlutterEngineCache.getInstance().get(CACHE_ID)?.let {
                    it.destroy()
                    FlutterEngineCache.getInstance().remove(CACHE_ID)
                }
            }
        }, TIMEOUT_MS)
    }

    private fun ensureHeadlessEngine(context: Context): MethodChannel? {
        val existing = FlutterEngineCache.getInstance().get(CACHE_ID)
        if (existing != null) {
            return MethodChannel(existing.dartExecutor.binaryMessenger, CHANNEL)
        }
        var engine: FlutterEngine? = null
        return try {
            engine = FlutterEngine(context)
            val appBundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(appBundlePath, "notificationActionMain"),
            )
            FlutterEngineCache.getInstance().put(CACHE_ID, engine)
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        } catch (_: Exception) {
            engine?.destroy()
            null
        }
    }
}
