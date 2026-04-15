// GENERATED TEMPLATE. This project expects FlutterFire to generate the real values.
// If you prefer automatic setup: run RUN_SETUP_WINDOWS.bat at the repo root.
// That script runs `flutterfire configure` and will overwrite this file.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return web;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB74Dm4WiLMHYdSiWPvB2yTzNWsINVBvWo',
    appId: '1:157235497908:web:4f702c7a670d76204ac0e1',
    messagingSenderId: '157235497908',
    projectId: 'gestaoyahweh-21e23',
    authDomain: 'gestaoyahweh-21e23.firebaseapp.com',
    storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
    measurementId: 'G-9N6YEP8XNW',
  );

  // ⚠️ Replace via `flutterfire configure`

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDgbGHUg1MfsXjR8KPzmel-nSFFFrPoyhs',
    appId: '1:157235497908:android:04c65d48c7d9fd094ac0e1',
    messagingSenderId: '157235497908',
    projectId: 'gestaoyahweh-21e23',
    storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDOqG8N_bW50rVt-Kob7mQDcYImNej0rGs',
    appId: '1:157235497908:ios:5c2a89577e79e39b4ac8e1',
    messagingSenderId: '157235497908',
    projectId: 'gestaoyahweh-21e23',
    storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
    iosClientId: '157235497908-u49j3hncrrnk22s7cm1ntrfqif9c40fj.apps.googleusercontent.com',
    iosBundleId: 'com.gestaoyaweh.app',
  );

}