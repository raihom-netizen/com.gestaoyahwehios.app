package com.gestaoyahweh.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

/// local_auth (biometria) exige FragmentActivity no Android — ver pub.dev local_auth.
/// Android 15+ (SDK 35): edge-to-edge por defeito; [enableEdgeToEdge] alinha com recuos/insets.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
