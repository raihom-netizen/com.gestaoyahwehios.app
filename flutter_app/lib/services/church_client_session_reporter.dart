import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:gestao_yahweh/utils/admin_user_search.dart';

/// Grava em `users/{uid}` a última plataforma do cliente (web / android / ios …)
/// para o painel master (Controle 360).
///
/// Só atualiza se o perfil **já existir** com e-mail completo — evita doc fantasma.
Future<void> reportChurchClientSessionToUserDoc() async {
  final u = firebaseDefaultAuth.currentUser;
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
  await patchUsersDocIfIdentified(
    db: firebaseDefaultFirestore,
    uid: u.uid,
    patch: {
      'lastClientPlatform': p,
      'lastClientPlatformAt': FieldValue.serverTimestamp(),
    },
  );
}
