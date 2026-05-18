package com.gestaoyahweh.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// local_auth (biometria) exige FragmentActivity no Android — ver pub.dev local_auth.
/// Android 15+ (SDK 35): edge-to-edge por defeito; [enableEdgeToEdge] alinha com recuos/insets.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.gestaoyahweh.app/deep_link"
    private var deepLinkChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deepLinkChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        deepLinkChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPath" -> result.success(extractPath(intent))
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = extractPath(intent) ?: return
        deepLinkChannel?.invokeMethod("onDeepLink", path)
    }

    private fun extractPath(intent: Intent?): String? {
        val data: Uri = intent?.data ?: return null
        val path = data.encodedPath ?: "/"
        val query = data.encodedQuery
        return if (query.isNullOrEmpty()) path else "$path?$query"
    }
}
