import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Grava em `users/{uid}` a última plataforma do cliente (web / android / ios …)
/// para o painel master (Controle 360).
void reportChurchClientSessionToUserDoc() {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) return;
  final String p;
  if (kIsWeb) {
    p = 'web';
  } else {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        p = 'android';
        break;
      case TargetPlatform.iOS:
        p = 'ios';
        break;
      default:
        p = defaultTargetPlatform.name;
    }
  }
  FirebaseFirestore.instance.collection('users').doc(u.uid).set(
    {
      'lastClientPlatform': p,
      'lastClientPlatformAt': FieldValue.serverTimestamp(),
    },
    SetOptions(merge: true),
  );
}
