import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

/// Acesso Firebase após bootstrap — mesmo padrão pedido para paridade Chat / Avisos / Eventos.
///
/// Preferir estes métodos em serviços de publicação em vez de campos estáticos
/// `final _db = FirebaseFirestore.instance`.
abstract final class FirebaseService {
  FirebaseService._();

  static Future<FirebaseFirestore> firestore({bool requireAuth = false}) async {
    await FirebaseBootstrap.ensureInitialized();
    if (requireAuth) {
      await FirebaseBootstrapService.ensureReady(requireAuthSession: true);
    }
    return FirebaseBootstrapService.firestore;
  }

  static Future<FirebaseStorage> storage() async {
    await FirebaseBootstrapService.ensureReadyForMediaUpload();
    return FirebaseBootstrapService.storage;
  }

  static Future<FirebaseAuth> auth() async {
    await FirebaseBootstrap.ensureInitialized();
    await FirebaseBootstrapService.ensureReady(requireAuthSession: false);
    return FirebaseBootstrapService.auth;
  }
}
