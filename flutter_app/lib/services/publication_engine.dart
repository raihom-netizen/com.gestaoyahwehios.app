import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/church_tenant_write_log.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firestore_write_guard.dart';
import 'package:gestao_yahweh/services/church_data_service.dart';
import 'package:gestao_yahweh/services/church_performance_cache_service.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_doc_service.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';

/// Tipos de conteúdo publicável — **único motor** (avisos, eventos, mural, feed público).
enum PublicationKind {
  aviso,
  evento,
  noticia,
  mural,
  feedPublico,
}

/// Fase da distribuição (Firestore já gravado — nunca cancelar publicação).
enum PublicationDistributionPhase {
  afterFirestoreSave,
  afterMediaFinalized,
}

/// Pedido de gravação Firestore (fase obrigatória).
class PublicationSaveRequest {
  const PublicationSaveRequest({
    required this.docRef,
    required this.tenantId,
    required this.kind,
    required this.payload,
    required this.isNewDoc,
    this.merge,
    this.publicSite = true,
    this.pendingPhotoCount = 0,
  });

  final DocumentReference<Map<String, dynamic>> docRef;
  final String tenantId;
  final PublicationKind kind;
  final Map<String, dynamic> payload;
  final bool isNewDoc;
  final bool? merge;
  final bool publicSite;
  final int pendingPhotoCount;

  String get postType => _postTypeFromKind(kind);

  static String _postTypeFromKind(PublicationKind k) {
    switch (k) {
      case PublicationKind.aviso:
      case PublicationKind.mural:
      case PublicationKind.feedPublico:
        return 'aviso';
      case PublicationKind.evento:
      case PublicationKind.noticia:
        return 'evento';
    }
  }

  bool get isEvento => postType == 'evento';
}

/// **Publication Engine** — aviso, evento, notícia, mural, feed público.
///
/// Ordem fixa após gravação Firestore (background; falha num passo **não** desfaz o post):
/// dashboard → painel → feed (streams locais) → site público → push (CF) → WhatsApp (opcional).
abstract final class PublicationEngine {
  PublicationEngine._();

  static const String statusProcessing = MuralFastPublishService.stateUploading;
  static const String statusPublished = MuralFastPublishService.statePublished;
  static const String statusFailed = MuralFastPublishService.stateFailed;
  static const String statusDraft = MuralFastPublishService.stateDraft;

  static const int kMaxPhotosPerPost = 5;
  static const int kMaxVideosPerPost = 1;

  // —— Fase 1: Firestore (bloqueante; falha = publicação não concluída) ——

  static Future<String> saveFirestore(PublicationSaveRequest request) async {
    await ensureFirebaseCore(requireAuth: true);
    final patch = _buildFirestorePatch(request);
    final merge = request.merge ?? !request.isNewDoc;
    try {
      await ChurchDataService.instance.setTenantDocument(
        ref: request.docRef,
        data: patch,
        merge: merge,
        module: request.postType,
      );
    } catch (e, st) {
      ChurchPublishFlowLog.firestoreError(e, st);
      rethrow;
    }
    FeedPublishPreflight.firestoreSaveOk(isEvento: request.isEvento);
    ChurchTenantWriteLog.publishStubCommitted(
      request.docRef.path,
      module: request.postType,
    );
    if (request.isEvento) {
      ChurchPublishFlowLog.eventoFirestoreOk();
    } else {
      ChurchPublishFlowLog.avisoFirestoreOk();
    }
    return request.docRef.id;
  }

  static Map<String, dynamic> _buildFirestorePatch(PublicationSaveRequest request) {
    final patch = FirestoreWriteGuard.stripHeavyFields(
      Map<String, dynamic>.from(request.payload),
    );
    patch['publishState'] = request.pendingPhotoCount > 0
        ? (request.isNewDoc
            ? EntityPublishStatus.creating
            : statusProcessing)
        : statusPublished;
    FirestoreWriteGuard.applyMuralPublishMetaPatch(
      patch,
      isNewDoc: request.isNewDoc,
      pendingPhotoCount: request.pendingPhotoCount,
      clearPublishError: true,
    );
    patch['updatedAt'] = FieldValue.serverTimestamp();
    return patch;
  }

  /// Grava Firestore e dispara distribuição em background (não bloqueia UI).
  static Future<String> publishFirestoreFirst({
    required PublicationSaveRequest request,
    PublicationDistributionPhase distributionPhase =
        PublicationDistributionPhase.afterFirestoreSave,
  }) async {
    final postId = await saveFirestore(request);
    scheduleDistribution(
      tenantId: request.tenantId,
      kind: request.kind,
      postId: postId,
      isNewDoc: request.isNewDoc,
      publicSite: request.publicSite,
      phase: distributionPhase,
    );
    return postId;
  }

  /// Publicação imediata sem fotos novas.
  static Future<String> publishNow({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required PublicationKind kind,
    required Map<String, dynamic> payload,
    required bool isNewDoc,
    bool publicSite = true,
  }) =>
      publishFirestoreFirst(
        request: PublicationSaveRequest(
          docRef: docRef,
          tenantId: tenantId,
          kind: kind,
          payload: payload,
          isNewDoc: isNewDoc,
          publicSite: publicSite,
        ),
      );

  /// Firestore → upload fotos em background (padrão Controle Total).
  static Future<String> publishWithPhotosInBackground({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required PublicationKind kind,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    required int pendingPhotoCount,
    bool publicSite = true,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
  }) async {
    final request = PublicationSaveRequest(
      docRef: docRef,
      tenantId: tenantId,
      kind: kind,
      payload: corePayload,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
      pendingPhotoCount: pendingPhotoCount,
    );
    final postId = await publishFirestoreFirst(request: request);
    if (pendingPhotoCount <= 0) {
      return postId;
    }

    Future<void> onMediaDone() async {
      scheduleDistribution(
        tenantId: tenantId,
        kind: kind,
        postId: postId,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
        phase: PublicationDistributionPhase.afterMediaFinalized,
      );
    }

    ChurchTenantWriteLog.publishBackgroundStart(docRef.path, module: request.postType);
    ChurchPublishFlowLog.uploadStart('${request.postType} $postId');

    final postType = request.postType;
    if (kIsWeb) {
      final images = newImagesBytes ?? const <Uint8List>[];
      if (images.isEmpty) {
        throw StateError('Não foi possível ler as fotos para enviar.');
      }
      MuralFastPublishService.scheduleBackgroundImageFinalize(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        newImages: images,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: MuralPostMediaPayload.buildMediaFields,
        onPublished: onMediaDone,
      );
    } else {
      final paths = newImagePaths
              ?.map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      if (paths.isEmpty) {
        throw StateError('Não foi possível ler as fotos para enviar.');
      }
      MuralFastPublishService.scheduleBackgroundImageFinalizeFromPaths(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        localPaths: paths,
        existingUrls: existingUrls,
        startSlotIndex: startSlotIndex,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: MuralPostMediaPayload.buildMediaFields,
        onPublished: onMediaDone,
      );
    }
    return postId;
  }

  /// Distribuição pós-publicação — **nunca** reverte o documento Firestore.
  static void scheduleDistribution({
    required String tenantId,
    required PublicationKind kind,
    required String postId,
    required bool isNewDoc,
    required bool publicSite,
    PublicationDistributionPhase phase =
        PublicationDistributionPhase.afterFirestoreSave,
  }) {
    unawaited(
      _runDistribution(
        tenantId: tenantId.trim(),
        kind: kind,
        postId: postId,
        isNewDoc: isNewDoc,
        publicSite: publicSite,
        phase: phase,
      ),
    );
  }

  static Future<void> _runDistribution({
    required String tenantId,
    required PublicationKind kind,
    required String postId,
    required bool isNewDoc,
    required bool publicSite,
    required PublicationDistributionPhase phase,
  }) async {
    if (tenantId.isEmpty) return;
    ChurchPublishFlowLog.phase(
      'DISTRIBUTION_${phase.name}_${kind.name}_$postId',
    );

    await _distStep('dashboard', () async {
      if (!isNewDoc) return;
      await ChurchTenantDashboardDocService.mergeCounters(
        tenantId,
        avisosDelta: kind == PublicationKind.aviso ||
                kind == PublicationKind.mural ||
                kind == PublicationKind.feedPublico
            ? 1
            : null,
        eventosDelta: kind == PublicationKind.evento ||
                kind == PublicationKind.noticia
            ? 1
            : null,
      );
    });

    await _distStep('panel', () async {
      await PanelDashboardSnapshotService.warmFromCallableIfStale(tenantId);
    });

    await _distStep('feed', () async {
      // Feed/mural no app: streams Firestore + cache local — nada bloqueante extra.
    });

    await _distStep('public_site', () async {
      if (!publicSite) return;
      await ChurchPerformanceCacheService.warmPublicFeedCacheFromCallableIfStale(
        tenantId,
      );
    });

    await _distStep('push', () async {
      // Push FCM: Cloud Functions `pushNovoConteudo.ts` após write Firestore.
      // Cliente não envia push — evita duplicar e travar publicação.
    });

    await _distStep('whatsapp', () async {
      // WhatsApp automático: só se tenant tiver integração ativa (futuro).
      // Partilha manual: [church_noticia_share_sheet].
    });

    if (kind == PublicationKind.evento || kind == PublicationKind.noticia) {
      ChurchPublishFlowLog.moduleFinalOk(isEvento: true);
    } else {
      ChurchPublishFlowLog.moduleFinalOk(isEvento: false);
    }
  }

  static Future<void> _distStep(
    String name,
    Future<void> Function() action,
  ) async {
    try {
      ChurchPublishFlowLog.phase('DIST_$name');
      await action().timeout(const Duration(seconds: 50));
      ChurchPublishFlowLog.phase('DIST_${name}_OK');
    } catch (e, st) {
      ChurchPublishFlowLog.logCatch(e, st, label: 'DIST_$name');
    }
  }

  static PublicationKind kindFromPostType(String postType) {
    final t = postType.trim().toLowerCase();
    if (t == 'aviso') return PublicationKind.aviso;
    if (t == 'evento') return PublicationKind.evento;
    if (t == 'noticia') return PublicationKind.noticia;
    if (t == 'feed' || t == 'feed_publico') return PublicationKind.feedPublico;
    return PublicationKind.mural;
  }
}
