import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/member_document_resolve.dart';

/// Upload do certificado (.p12 / .pfx) para o Storage **restrito** e referência no perfil do usuário logado.
///
/// **Segurança:** não gravar senha do certificado no Firestore. Use [FlutterSecureStorage] apenas no dispositivo
/// se o gestor optar por “lembrar PIN” (opcional na UI).
class CertificadoDigitalService {
  CertificadoDigitalService._();

  static Future<DocumentReference<Map<String, dynamic>>?> _membroRefForUid(
    String tenantId,
    String uid,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || uid.isEmpty) return null;
    final col = MemberDocumentResolve.membrosCol(
      FirebaseFirestore.instance,
      tid,
    );
    try {
      final byId = await col.doc(uid).get();
      if (byId.exists) return byId.reference;
    } catch (_) {}
    try {
      final q = await col.where('authUid', isEqualTo: uid).limit(1).get();
      if (q.docs.isNotEmpty) return q.docs.first.reference;
    } catch (_) {}
    return null;
  }

  /// Nome do ficheiro .p12 exibido na UI (prioriza [users], depois [membros]).
  static Future<String?> certificateFileNameForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final ud = userDoc.data();
      var n = (ud?['certificadoDigitalFileName'] ?? '').toString().trim();
      if (n.isNotEmpty) return n;
      final tid = (ud?['certificadoDigitalTenantId'] ??
              ud?['tenantId'] ??
              ud?['igrejaId'] ??
              '')
          .toString()
          .trim();
      if (tid.isEmpty) return null;
      final mRef = await _membroRefForUid(tid, uid);
      if (mRef == null) return null;
      final m = await mRef.get();
      n = (m.data()?['certificadoDigitalFileName'] ?? '').toString().trim();
      return n.isEmpty ? null : n;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> storagePathForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = userDoc.data();
      var p = (data?['certificadoDigitalStoragePath'] ?? '').toString().trim();
      if (p.isNotEmpty) return p;
      final tid = (data?['certificadoDigitalTenantId'] ??
              data?['tenantId'] ??
              data?['igrejaId'] ??
              '')
          .toString()
          .trim();
      if (tid.isEmpty) return null;
      final mRef = await _membroRefForUid(tid, uid);
      if (mRef == null) return null;
      final m = await mRef.get();
      p = (m.data()?['certificadoDigitalStoragePath'] ?? '')
          .toString()
          .trim();
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
    final payload = <String, dynamic>{
      'certificadoDigitalStoragePath': path,
      'certificadoDigitalFileName': safeName,
      'certificadoDigitalUpdatedAt': FieldValue.serverTimestamp(),
      'certificadoDigitalTenantId': tid,
    };
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
          payload,
          SetOptions(merge: true),
        );
    try {
      final mRef = await _membroRefForUid(tid, uid);
      if (mRef != null) {
        await mRef.set(payload, SetOptions(merge: true));
      }
    } catch (e, st) {
      debugPrint('CertificadoDigitalService.membros mirror: $e\n$st');
    }
  }

  static Future<void> removeCertificateReferenceForCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final deletes = <String, dynamic>{
      'certificadoDigitalStoragePath': FieldValue.delete(),
      'certificadoDigitalFileName': FieldValue.delete(),
      'certificadoDigitalUpdatedAt': FieldValue.delete(),
      'certificadoDigitalTenantId': FieldValue.delete(),
    };
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    Map<String, dynamic>? userData;
    try {
      userData = (await userRef.get()).data();
    } catch (_) {}
    await userRef.set(deletes, SetOptions(merge: true));
    final tid = (userData?['certificadoDigitalTenantId'] ??
            userData?['tenantId'] ??
            userData?['igrejaId'] ??
            '')
        .toString()
        .trim();
    if (tid.isEmpty) return;
    try {
      final mRef = await _membroRefForUid(tid, uid);
      if (mRef != null) {
        await mRef.set(deletes, SetOptions(merge: true));
      }
    } catch (e, st) {
      debugPrint('CertificadoDigitalService.membros remove: $e\n$st');
    }
  }
}
