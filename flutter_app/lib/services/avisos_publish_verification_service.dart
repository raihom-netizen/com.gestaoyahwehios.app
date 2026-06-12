import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/core/church_publish_state.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageObjectPathFromHttpUrl;

/// Verificação obrigatória pós-gravação de avisos — evita falso sucesso.
abstract final class AvisosPublishVerificationService {
  AvisosPublishVerificationService._();

  static const String kPublishVerifyFailedMessage =
      'Falha ao publicar aviso.\nDocumento não localizado no Firestore.';

  static const String kStorageVerifyFailedMessage =
      'Falha ao publicar mídia do aviso.\nArquivo não confirmado no Storage.';

  static String? _lastError;

  static String? get lastError => _lastError;

  static void rememberLastError(Object error) {
    _lastError = error.toString();
  }

  static void clearLastError() => _lastError = null;

  /// PASSO 1 — resolve tenant operacional e aborta aliases legados.
  static Future<String> resolveTenantForPublish({
    required String seedTenantId,
    String? userUid,
  }) async {
    final resolved = ChurchPublishContext.churchIdForPublish(seedTenantId);
    debugPrint('CHURCH_ID (avisos): $resolved');
    return resolved;
  }

  static void assertOperationalWriteTenant(String igrejaId) {
    final t = igrejaId.trim();
    if (t.isEmpty) throw StateError('churchId vazio.');
  }

  /// Grava rascunho antes do upload — falha mantém conteúdo em draft.
  static Future<void> ensureDraft(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    await docRef.set(ChurchPublishState.draftPatch(), SetOptions(merge: true));
  }

  /// Garante path `igrejas/{igrejaId}/avisos/{docId}` — proíbe coleções legadas.
  static void assertAvisosCollectionPath(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length < 4 ||
        parts[0] != 'igrejas' ||
        parts[2] != ChurchTenantPostsCollections.avisos) {
      throw StateError(
        'Coleção incorreta para aviso: ${ref.path}. '
        'Esperado: igrejas/{igrejaId}/${ChurchTenantPostsCollections.avisos}/',
      );
    }
    assertOperationalWriteTenant(parts[1]);
  }

  static DocumentReference<Map<String, dynamic>> avisoDocRef({
    required String igrejaId,
    required String docId,
  }) {
    final ref = ChurchOperationalPaths.churchDoc(igrejaId.trim())
        .collection(ChurchTenantPostsCollections.avisos)
        .doc(docId.trim());
    assertAvisosCollectionPath(ref);
    return ref;
  }

  static String collectionPathFor(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/${ChurchTenantPostsCollections.avisos}';

  static List<String> storagePathsFromUrls(Iterable<String> urls) {
    final out = <String>[];
    for (final u in urls) {
      final t = u.trim();
      if (t.contains('igrejas/') &&
          !t.startsWith('http://') &&
          !t.startsWith('https://')) {
        out.add(t);
        continue;
      }
      final p = firebaseStorageObjectPathFromHttpUrl(t);
      if (p != null && p.isNotEmpty) out.add(p);
    }
    return out;
  }

  /// Confirma fotos no Storage antes de marcar aviso como publicado.
  static Future<void> verifyStorageMetadata({
    Iterable<String> photoPaths = const [],
    Duration timeout = ChurchStorageMetadataVerify.kDefaultTimeout,
    int maxAttempts = ChurchStorageMetadataVerify.kMaxAttempts,
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertAllExist(
        photoPaths,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } catch (e) {
      rememberLastError(kStorageVerifyFailedMessage);
      rethrow;
    }
  }

  /// PASSO 4 — confirma que o Firestore gravou o documento.
  static Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
  }) async {
    assertAvisosCollectionPath(docRef);
    final check = await docRef.get(
      GetOptions(
        source: preferServer ? Source.server : Source.serverAndCache,
      ),
    );
    if (!check.exists) {
      rememberLastError(kPublishVerifyFailedMessage);
      throw StateError(kPublishVerifyFailedMessage);
    }
    return check;
  }

  static Future<void> logPublishPhase({
    required String phase,
    required String igrejaId,
    required String uid,
    required String titulo,
    required String docId,
    String? storagePath,
  }) async {
    await SystemLogService.record(
      module: 'avisos',
      message: 'publish_$phase',
      tenantId: igrejaId,
      canonicalId: igrejaId,
      severity: phase == 'after' ? 'info' : 'debug',
      extra: <String, dynamic>{
        'igrejaId': igrejaId,
        'uid': uid,
        'titulo': titulo,
        'docId': docId,
        'collection': collectionPathFor(igrejaId),
        if (storagePath != null && storagePath.isNotEmpty)
          'storagePath': storagePath,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}

/// Relatório do botão «Diagnóstico Avisos».
class AvisosDiagnosticReport {
  const AvisosDiagnosticReport({
    required this.tenantAtual,
    required this.tenantResolvido,
    required this.colecaoUtilizada,
    required this.quantidadeAvisos,
    this.ultimoAvisoTitulo,
    this.ultimoAvisoDocId,
    this.ultimoAvisoCreatedAt,
    this.ultimoErro,
  });

  final String tenantAtual;
  final String tenantResolvido;
  final String colecaoUtilizada;
  final int quantidadeAvisos;
  final String? ultimoAvisoTitulo;
  final String? ultimoAvisoDocId;
  final DateTime? ultimoAvisoCreatedAt;
  final String? ultimoErro;
}

abstract final class AvisosDiagnosticService {
  AvisosDiagnosticService._();

  static Future<AvisosDiagnosticReport> run({
    required String seedTenantId,
    String? userUid,
  }) async {
    String resolved = seedTenantId.trim();
    String? ultimoErro = AvisosPublishVerificationService.lastError;

    try {
      resolved = await AvisosPublishVerificationService.resolveTenantForPublish(
        seedTenantId: seedTenantId,
        userUid: userUid,
      );
    } catch (e) {
      ultimoErro = e.toString();
    }

    final colecao = AvisosPublishVerificationService.collectionPathFor(resolved);
    var count = 0;
    String? ultimoTitulo;
    String? ultimoDocId;
    DateTime? ultimoCreatedAt;

    try {
      final snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(resolved)
          .collection(ChurchTenantPostsCollections.avisos)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.serverAndCache));

      count = snap.docs.length;
      if (snap.docs.isNotEmpty) {
        final latest = snap.docs.first;
        ultimoDocId = latest.id;
        final data = latest.data();
        ultimoTitulo = (data['title'] ?? '').toString();
        final raw = data['createdAt'];
        if (raw is Timestamp) ultimoCreatedAt = raw.toDate();
      }
    } catch (e) {
      ultimoErro = e.toString();
    }

    return AvisosDiagnosticReport(
      tenantAtual: seedTenantId.trim(),
      tenantResolvido: resolved,
      colecaoUtilizada: colecao,
      quantidadeAvisos: count,
      ultimoAvisoTitulo: ultimoTitulo,
      ultimoAvisoDocId: ultimoDocId,
      ultimoAvisoCreatedAt: ultimoCreatedAt,
      ultimoErro: ultimoErro,
    );
  }
}
