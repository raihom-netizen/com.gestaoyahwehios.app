import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';

/// Upload do certificado (.p12 / .pfx) para o Storage **restrito** e referência no perfil do usuário logado.
///
/// **Segurança:** não gravar senha do certificado no Firestore. Use [FlutterSecureStorage] apenas no dispositivo
/// se o gestor optar por “lembrar PIN” (opcional na UI).
class CertificadoDigitalService {
  CertificadoDigitalService._();

  static Future<String?> storagePathForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final p = (doc.data()?['certificadoDigitalStoragePath'] ?? '').toString().trim();
      return p.isEmpty ? null : p;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> downloadCertificateBytes(String storagePath) async {
    final p = storagePath.trim();
    if (p.isEmpty) return null;
    try {
      final ref = FirebaseStorage.instance.ref(p);
      final data = await ref.getData(6 * 1024 * 1024);
      return data;
    } catch (e, st) {
      debugPrint('CertificadoDigitalService.downloadCertificateBytes: $e\n$st');
      return null;
    }
  }

  /// Faz upload e grava metadados em `users/{uid}` (o próprio usuário pode atualizar).
  static Future<void> uploadPfxForCurrentUser({
    required String tenantId,
    required Uint8List bytes,
    required String originalFileName,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('Usuário não autenticado');
    final tid = tenantId.trim();
    if (tid.isEmpty) throw StateError('Igreja inválida');
    if (bytes.isEmpty) throw StateError('Arquivo vazio');
    final safeName = originalFileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path = 'igrejas/$tid/certificados_gestor/${uid}_${DateTime.now().millisecondsSinceEpoch}.p12';
    await MediaUploadService.uploadBytesWithRetry(
      storagePath: path,
      bytes: bytes,
      contentType: 'application/x-pkcs12',
      cacheControl: 'private, no-cache',
    );
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'certificadoDigitalStoragePath': path,
        'certificadoDigitalFileName': safeName,
        'certificadoDigitalUpdatedAt': FieldValue.serverTimestamp(),
        'certificadoDigitalTenantId': tid,
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> removeCertificateReferenceForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'certificadoDigitalStoragePath': FieldValue.delete(),
        'certificadoDigitalFileName': FieldValue.delete(),
        'certificadoDigitalUpdatedAt': FieldValue.delete(),
        'certificadoDigitalTenantId': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }
}
