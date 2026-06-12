import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageObjectPathFromHttpUrl;

/// Verificação obrigatória pós-gravação de eventos — evita falso sucesso.
abstract final class EventosPublishVerificationService {
  EventosPublishVerificationService._();

  static const String kPublishVerifyFailedMessage =
      'Falha ao publicar evento.\nDocumento não localizado no Firestore.';

  static const String kStorageVerifyFailedMessage =
      'Falha ao publicar evento.\nMídia não confirmada no Storage.';

  static String? _lastError;

  static String? get lastError => _lastError;

  static void rememberLastError(Object error) {
    _lastError = error.toString();
  }

  static void clearLastError() => _lastError = null;

  static Future<String> resolveTenantForPublish({
    required String seedTenantId,
    String? userUid,
  }) async {
    final resolved = ChurchPublishContext.churchIdForPublish(seedTenantId);
    debugPrint('CHURCH_ID (eventos): $resolved');
    return resolved;
  }

  static void assertEventosCollectionPath(
    DocumentReference<Map<String, dynamic>> ref,
  ) {
    final parts = ref.path.split('/');
    if (parts.length < 4 ||
        parts[0] != 'igrejas' ||
        parts[2] != ChurchTenantPostsCollections.eventos) {
      throw StateError(
        'Coleção incorreta para evento: ${ref.path}. '
        'Esperado: igrejas/{igrejaId}/${ChurchTenantPostsCollections.eventos}/',
      );
    }
    if (parts[1].trim().isEmpty) {
      throw StateError('churchId inválido: ${ref.path}');
    }
  }

  static DocumentReference<Map<String, dynamic>> eventoDocRef({
    required String igrejaId,
    required String docId,
  }) {
    final ref = ChurchOperationalPaths.churchDoc(igrejaId.trim())
        .collection(ChurchTenantPostsCollections.eventos)
        .doc(docId.trim());
    assertEventosCollectionPath(ref);
    return ref;
  }

  static String collectionPathFor(String igrejaId) =>
      'igrejas/${igrejaId.trim()}/${ChurchTenantPostsCollections.eventos}';

  static List<String> storagePathsFromUrls(Iterable<String> urls) {
    final out = <String>[];
    for (final u in urls) {
      final p = firebaseStorageObjectPathFromHttpUrl(u.trim());
      if (p != null && p.isNotEmpty) out.add(p);
    }
    return out;
  }

  static String? hostedVideoStoragePath({
    required String igrejaId,
    required String eventoId,
    int slot = 0,
  }) =>
      ChurchStorageLayout.eventHostedVideoMp4Path(igrejaId, eventoId, slot);

  /// PASSO 5 — confirma fotos e vídeo no Storage.
  static Future<void> verifyStorageMetadata({
    Iterable<String> photoPaths = const [],
    String? videoPath,
    Duration timeout = ChurchStorageMetadataVerify.kDefaultTimeout,
    int maxAttempts = ChurchStorageMetadataVerify.kMaxAttempts,
  }) async {
    try {
      await ChurchStorageMetadataVerify.assertAllExist(
        photoPaths,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
      final vp = videoPath?.trim() ?? '';
      if (vp.isNotEmpty) {
        await ChurchStorageMetadataVerify.assertExists(
          vp,
          timeout: timeout,
          maxAttempts: maxAttempts,
        );
      }
    } catch (e) {
      rememberLastError(kStorageVerifyFailedMessage);
      rethrow;
    }
  }

  /// PASSO 7 — confirma documento no Firestore.
  static Future<DocumentSnapshot<Map<String, dynamic>>> verifyDocumentExists(
    DocumentReference<Map<String, dynamic>> docRef, {
    bool preferServer = true,
  }) async {
    assertEventosCollectionPath(docRef);
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
    required String eventoId,
    List<String>? fotos,
    String? videoPath,
    Object? erro,
  }) async {
    await SystemLogService.record(
      module: 'eventos',
      message: erro != null ? 'publish_error' : 'publish_$phase',
      tenantId: igrejaId,
      canonicalId: igrejaId,
      severity: erro != null ? 'error' : (phase == 'after' ? 'info' : 'debug'),
      error: erro,
      extra: <String, dynamic>{
        'uid': uid,
        'igrejaId': igrejaId,
        'eventoId': eventoId,
        'titulo': titulo,
        'collection': collectionPathFor(igrejaId),
        if (fotos != null && fotos.isNotEmpty) 'fotos': fotos,
        if (videoPath != null && videoPath.isNotEmpty) 'video': videoPath,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }
}

class EventosDiagnosticReport {
  const EventosDiagnosticReport({
    required this.tenantAtual,
    required this.tenantResolvido,
    required this.colecaoUtilizada,
    required this.quantidadeEventos,
    this.ultimoEventoTitulo,
    this.ultimoEventoDocId,
    this.ultimoEventoCreatedAt,
    this.fotosEncontradas = 0,
    this.videoEncontrado = false,
    this.ultimoErro,
  });

  final String tenantAtual;
  final String tenantResolvido;
  final String colecaoUtilizada;
  final int quantidadeEventos;
  final String? ultimoEventoTitulo;
  final String? ultimoEventoDocId;
  final DateTime? ultimoEventoCreatedAt;
  final int fotosEncontradas;
  final bool videoEncontrado;
  final String? ultimoErro;
}

abstract final class EventosDiagnosticService {
  EventosDiagnosticService._();

  static Future<EventosDiagnosticReport> run({
    required String seedTenantId,
    String? userUid,
  }) async {
    String resolved = seedTenantId.trim();
    String? ultimoErro = EventosPublishVerificationService.lastError;

    try {
      resolved = await EventosPublishVerificationService.resolveTenantForPublish(
        seedTenantId: seedTenantId,
        userUid: userUid,
      );
    } catch (e) {
      ultimoErro = e.toString();
    }

    final colecao = EventosPublishVerificationService.collectionPathFor(resolved);
    var count = 0;
    String? ultimoTitulo;
    String? ultimoDocId;
    DateTime? ultimoCreatedAt;
    var fotosCount = 0;
    var videoOk = false;

    try {
      final snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(resolved)
          .collection(ChurchTenantPostsCollections.eventos)
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get(const GetOptions(source: Source.serverAndCache));

      count = snap.docs.length;
      if (snap.docs.isNotEmpty) {
        final latest = snap.docs.first;
        ultimoDocId = latest.id;
        final data = latest.data();
        ultimoTitulo = (data['title'] ?? '').toString();
        final raw = data['createdAt'];
        if (raw is Timestamp) ultimoCreatedAt = raw.toDate();

        final fotos = data['fotos'];
        if (fotos is List) {
          fotosCount = fotos.length;
        } else {
          final paths = data['imageStoragePaths'];
          if (paths is List) fotosCount = paths.length;
        }
        final vp = (data['videoPath'] ?? '').toString().trim();
        if (vp.isNotEmpty) {
          try {
            await ChurchStorageMetadataVerify.assertExists(vp);
            videoOk = true;
          } catch (_) {}
        } else {
          final videos = data['videos'];
          if (videos is List && videos.isNotEmpty) videoOk = true;
        }
      }
    } catch (e) {
      ultimoErro = e.toString();
    }

    return EventosDiagnosticReport(
      tenantAtual: seedTenantId.trim(),
      tenantResolvido: resolved,
      colecaoUtilizada: colecao,
      quantidadeEventos: count,
      ultimoEventoTitulo: ultimoTitulo,
      ultimoEventoDocId: ultimoDocId,
      ultimoEventoCreatedAt: ultimoCreatedAt,
      fotosEncontradas: fotosCount,
      videoEncontrado: videoOk,
      ultimoErro: ultimoErro,
    );
  }
}
