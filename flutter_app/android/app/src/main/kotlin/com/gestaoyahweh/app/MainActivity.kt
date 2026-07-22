package com.gestaoyahweh.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val launcherChannelName = "gestaoyahweh/launcher"
private const val widgetSyncChannelName = "gestaoyahweh/widget_sync"
private const val widgetSyncPrefs = "gestaoyahweh_widget_sync"
private const val widgetSyncDueKey = "sync_due_ms"

/// local_auth (biometria) exige FragmentActivity no Android — ver pub.dev local_auth.
/// Android 15+ (SDK 35): edge-to-edge por defeito; [enableEdgeToEdge] alinha com recuos/insets.
class MainActivity : FlutterFragmentActivity() {
    private val deepLinkChannelName = "com.gestaoyahweh.app/deep_link"
    private var deepLinkChannel: MethodChannel? = null

    /** Índice do módulo vindo do widget (ou -1). */
    private var pendingOpenModuleIndex: Int = -1

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        captureOpenModuleFromIntent(intent)
        super.onCreate(savedInstanceState)
        try {
            WidgetSyncAlarmScheduler.scheduleNext(applicationContext)
        } catch (_: Throwable) {
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenModuleFromIntent(intent)
        val path = extractPath(intent) ?: return
        deepLinkChannel?.invokeMethod("onDeepLink", path)
    }

    private fun captureOpenModuleFromIntent(i: Intent?) {
        val v = i?.getIntExtra("gy_open_module", -1) ?: -1
        if (v >= 0) {
            pendingOpenModuleIndex = v
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        deepLinkChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deepLinkChannelName)
        deepLinkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPath" -> result.success(extractPath(intent))
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launcherChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingModule" -> {
                        val v = pendingOpenModuleIndex
                        pendingOpenModuleIndex = -1
                        result.success(v)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, widgetSyncChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleAlarms" -> {
                        try {
                            WidgetSyncAlarmScheduler.scheduleNext(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_FAILED", e.message, null)
                        }
                    }
                    "scheduleExpiryAlarm" -> {
                        try {
                            val expiryMs = (call.arguments as? Number)?.toLong() ?: 0L
                            if (expiryMs > 0L) {
                                WidgetSyncAlarmScheduler.scheduleExpiryAlarm(
                                    applicationContext,
                                    expiryMs,
                                )
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SCHEDULE_EXPIRY_FAILED", e.message, null)
                        }
                    }
                    "consumeSyncDue" -> {
                        try {
                            val prefs = applicationContext.getSharedPreferences(
                                widgetSyncPrefs,
                                Context.MODE_PRIVATE,
                            )
                            val dueMs = prefs.getLong(widgetSyncDueKey, 0L)
                            if (dueMs <= 0L) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            prefs.edit().remove(widgetSyncDueKey).apply()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CONSUME_FAILED", e.message, null)
                        }
                    }
                    "forceWidgetRedraw" -> {
                        try {
                            WidgetRedrawHelper.requestAllWidgetsRedraw(applicationContext)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("REDRAW_FAILED", e.message, null)
                        }
                    }
                    "persistWidgetJson" -> {
                        try {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<String, Any?>
                            val json = args?.get("json") as? String
                            val key = (args?.get("key") as? String)
                                ?: GestaoYahwehWidgetProvider.JSON_KEY
                            if (json.isNullOrBlank()) {
                                result.error("BAD_ARGS", "json required", null)
                                return@setMethodCallHandler
                            }
                            val ok = applicationContext
                                .getSharedPreferences(
                                    "HomeWidgetPreferences",
                                    Context.MODE_PRIVATE,
                                )
                                .edit()
                                .putString(key, json)
                                .commit()
                            WidgetRedrawHelper.requestAllWidgetsRedraw(applicationContext)
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("PERSIST_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun extractPath(intent: Intent?): String? {
        val data: Uri = intent?.data ?: return null
        val path = data.encodedPath ?: "/"
        val query = data.encodedQuery
        return if (query.isNullOrEmpty()) path else "$path?$query"
    }
}
